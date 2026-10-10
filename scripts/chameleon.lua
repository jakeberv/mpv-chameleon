-- mpv-chameleon: Your video adapts to your display.
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (c) 2026 mpv-chameleon contributors
local mp = require('mp')
local utils = require('mp.utils')
local options = require('mp.options')
local opts = {helper='~~/helpers/mpv-chameleon', debug=false, poll_interval=2,
              refresh_interval=15, timeout=5, debounce=0.10}
options.read_options(opts, 'chameleon')
local function bounded(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    return math.max(lo, math.min(hi, v))
end
opts.poll_interval = bounded(opts.poll_interval, 1, 60, 2)
opts.refresh_interval = bounded(opts.refresh_interval, 5, 300, 15)
opts.timeout = bounded(opts.timeout, 1, 30, 5)
opts.debounce = bounded(opts.debounce, 0.05, 1, 0.1)
local keys = {'target-prim', 'target-trc', 'target-gamut', 'target-peak',
              'tone-mapping', 'target-colorspace-hint-mode', 'target-colorspace-hint'}
local original, owned = {}, {}
local enabled, stopped = true, false
local generation, request_number = 0, 0
local pending, debounce, periodic
local last_display, mode, last_error
local last_query = -math.huge
-- Source classification is independent of display EDR capability. mpv may
-- infer absent tags, so these are effective decoder parameters, not proof
-- that the file contained explicit mastering metadata.
local function source_format()
    local p = mp.get_property_native('video-params')
    if type(p) ~= 'table' then return 'unknown' end
    if p.gamma == 'pq' and p.primaries == 'bt.2020' then return 'hdr10' end
    if p.gamma == 'hlg' then return 'hlg' end
    local sdr = {['bt.1886']=true, ['srgb']=true, ['gamma1.8']=true,
                 ['gamma2.0']=true, ['gamma2.2']=true, ['gamma2.4']=true,
                 ['gamma2.6']=true, ['gamma2.8']=true, ['prophoto']=true}
    if sdr[p.gamma] and type(p.primaries) == 'string' and p.primaries ~= 'unknown' then return 'sdr' end
    return 'unknown'
end
local last_source = source_format()
local function debug(s) if opts.debug then mp.msg.info(s) end end
local function warn(s)
    if s ~= last_error then mp.msg.warn(s); last_error = s end
end
local function prop(k) return mp.get_property(k) end
local function restore()
    for _,k in ipairs(keys) do
        if owned[k] ~= nil and prop(k) == owned[k] then mp.set_property(k, original[k]) end
    end
    owned = {}
    mode = nil
end
local function cancel()
    generation = generation + 1
    if debounce then debounce:kill(); debounce=nil end
    if pending then
        local p = pending; pending=nil
        if p.timer then p.timer:kill() end
        if p.id then mp.abort_async_command(p.id) end
    end
end
local function disable(reason)
    enabled=false
    cancel()
    restore()
    if reason then warn(reason) end
end
local function compatible()
    local platform = prop('platform')
    if platform and platform ~= 'darwin' and platform ~= 'macos' then return false, 'macOS is required' end
    local vo, context = prop('current-vo'), prop('current-gpu-context')
    if (vo and vo ~= '' and vo ~= 'gpu-next') or (context and context ~= '' and context ~= 'macvk') then
        return false, 'requires vo=gpu-next, gpu-api=vulkan, gpu-context=macvk; automation disabled'
    end
    for k, expected in pairs({['options/vo']='gpu-next', ['options/gpu-api']='vulkan', ['options/gpu-context']='macvk'}) do
        local value = prop(k)
        if value and value ~= '' and value ~= 'auto' and value ~= expected then
            return false, 'unsupported '..k..'; use gpu-next / vulkan / macvk'
        end
    end
    if prop('icc-profile-auto') == 'yes' or (prop('icc-profile') or '') ~= '' then
        return false, 'ICC overrides take precedence over target colors; disable ICC options to use chameleon'
    end
    if prop('target-colorspace-hint-strict') ~= 'yes' or prop('inverse-tone-mapping') == 'yes' then
        return false, 'requires target-colorspace-hint-strict=yes and inverse-tone-mapping=no'
    end
    return true
end
local function write(k,v)
    if prop(k) == v then owned[k]=v; return true end
    local ok,err = mp.set_property(k,v)
    if not ok then warn('cannot set '..k..': '..tostring(err)); return false end
    owned[k]=v
    return true
end
local function apply(next_mode)
    if not enabled or stopped then return false end
    local ok,reason = compatible()
    if not ok then disable(reason); return false end
    -- A profile or another script changed a property we control. Yield ownership
    -- rather than silently undoing the user's new policy on the next refresh.
    for k,v in pairs(owned) do
        if prop(k) ~= v then
            disable('color setting changed externally ('..k..'); automation disabled; use chameleon-enable to rebaseline')
            return false
        end
    end
    if next_mode == 'hdr' and source_format() ~= 'hdr10' then next_mode='sdr' end
    local target = {}
    if next_mode == 'hdr' then
        for _,k in ipairs(keys) do target[k]=original[k] end
        target['target-colorspace-hint-mode']='source'
        target['target-colorspace-hint']='yes'
    else
        target={['target-prim']='bt.709', ['target-trc']='srgb', ['target-gamut']='auto',
                ['target-peak']='auto',
                ['tone-mapping']=source_format() == 'sdr' and original['tone-mapping'] or 'bt.2390',
                ['target-colorspace-hint-mode']='target',
                ['target-colorspace-hint']='yes'}
    end
    local changed = false
    for _,k in ipairs(keys) do if prop(k) ~= target[k] then changed=true end end
    if not changed and mode == next_mode then return true end
    -- Remove old HDR signaling first; enable the completed target last. mpv
    -- has no atomic multi-property transaction, so this minimizes the hazard.
    if changed and not write('target-colorspace-hint','no') then return false end
    for _,k in ipairs(keys) do
        if not write(k,target[k]) then
            write('target-colorspace-hint','no')
            mode=nil
            mp.msg.error('output update incomplete; HDR signaling disabled; check mpv version/options')
            return false
        end
    end
    if mode ~= next_mode then
        mp.msg.info('Automatic display mode: '..next_mode..' (output policy applied)')
    end
    mode=next_mode
    return true
end
local function display()
    local names=mp.get_property_native('display-names')
    if type(names) ~= 'table' or #names ~= 1 or type(names[1]) ~= 'string' or names[1] == '' then return nil end
    return names[1]
end
local function decode(stdout)
    if type(stdout) ~= 'string' or #stdout > 262144 then return nil,'invalid helper output size' end
    local ok,data=pcall(utils.parse_json,stdout)
    if not ok or type(data) ~= 'table' or data.schema_version ~= 1 or type(data.displays) ~= 'table'
        or type(data.selection) ~= 'table' then return nil,'invalid helper JSON/schema' end
    local selected=data.selection
    if selected.status ~= 'exact' and selected.status ~= 'name' then
        return nil,'display identity is unknown or ambiguous; using SDR'
    end
    if type(selected.display_id) ~= 'number' then return nil,'invalid selected display ID' end
    local found
    for _,d in ipairs(data.displays) do
        if type(d) ~= 'table' or type(d.id) ~= 'number' then return nil,'invalid display record' end
        if d.id == selected.display_id then
            if found then return nil,'duplicate selected display ID' end
            found=d
        end
    end
    local value=found and found.potential_edr
    if type(value) ~= 'number' or value ~= value or value < 1 or value == math.huge then
        return nil,'invalid or unavailable EDR capability; using SDR'
    end
    return value > 1 and 'hdr' or 'sdr', nil, value
end
local check, schedule
schedule=function()
    if not enabled or stopped then return end
    if debounce then debounce:kill() end
    debounce=mp.add_timeout(opts.debounce,function() debounce=nil; check(true) end)
end
check=function(force)
    if not enabled or stopped or not mp.get_property_native('vo-configured',false) then return end
    local ok,reason=compatible()
    if not ok then disable(reason); return end
    local current=display()
    if current ~= last_display then
        last_display=current
        generation=generation+1
        debug('Display changed; querying capabilities')
        apply('sdr')
        force=true
    end
    if not current then apply('sdr'); return end
    if pending or (not force and mp.get_time()-last_query < opts.refresh_interval) then return end
    request_number=request_number+1
    local p={number=request_number,generation=generation,display=current}
    pending=p
    last_query=mp.get_time()
    local helper=mp.command_native({'expand-path',opts.helper})
    p.id=mp.command_native_async({name='subprocess',args={helper,'--display',current},
        capture_stdout=true,capture_stderr=true,playback_only=false,capture_size=262144},function(success,result)
        if pending ~= p then return end
        pending=nil
        if p.timer then p.timer:kill() end
        if not enabled or stopped then return end
        if p.generation ~= generation or p.display ~= display() then
            debug('Discarded stale capability response'); schedule(); return
        end
        if not success or type(result) ~= 'table' or result.status ~= 0 then
            warn('display helper failed; using SDR. Run install.sh again and check helper permissions')
            apply('sdr'); return
        end
        local next_mode,err,value=decode(result.stdout)
        if not next_mode then warn(err); apply('sdr'); return end
        last_error=nil
        debug('EDR potential='..tostring(value)..'; display capability='..next_mode..'; source='..source_format())
        apply(next_mode)
    end)
    p.timer=mp.add_timeout(opts.timeout,function()
        if pending ~= p then return end
        pending=nil
        if p.id then mp.abort_async_command(p.id) end
        warn('display helper timed out; using SDR; retrying on next capability refresh')
        apply('sdr')
        if p.generation ~= generation or p.display ~= display() then schedule() end
    end)
end
local function capture()
    for _,k in ipairs(keys) do
        original[k]=prop(k)
        if original[k] == nil then return false,'missing mpv property '..k..'; mpv 0.41+ is required' end
    end
    return compatible()
end
-- Do not run alongside the original prototype in the ordinary autoload path.
local legacy=mp.command_native({'expand-path','~~/scripts/auto-hdr.lua'})
if utils.file_info(legacy) then
    mp.msg.error('auto-hdr.lua is still installed; migrate with install.sh before loading chameleon')
    return
end
local owner_path='user-data/mpv-chameleon/owner'
if mp.get_property_native(owner_path) then mp.msg.warn('another chameleon script is already active'); return end
mp.set_property_native(owner_path,mp.get_script_name())
local ok,reason=capture()
if not ok then enabled=false; warn(reason) else apply('sdr') end
mp.observe_property('display-names','native',function()
    local current=display()
    if current ~= last_display then
        last_display=current; generation=generation+1
        if enabled then apply('sdr'); schedule() end
    end
end)
mp.observe_property('video-params','native',function()
    local current=source_format()
    if current ~= last_source then
        last_source=current; generation=generation+1
        debug('Source format changed: '..current)
        if enabled then apply('sdr'); schedule() end
    end
end)
mp.observe_property('vo-configured','bool',function()
    if mp.get_property_native('vo-configured',false) then schedule() else cancel() end
end)
mp.observe_property('fullscreen','bool',function() generation=generation+1; schedule() end)
mp.add_hook('on_load',50,function() cancel(); apply('sdr') end)
mp.register_event('file-loaded',function() generation=generation+1; schedule() end)
mp.register_event('video-reconfig',function() schedule() end)
mp.register_event('shutdown',function()
    stopped=true; cancel(); if periodic then periodic:kill() end; restore()
    mp.set_property_native(owner_path,nil)
end)
mp.register_script_message('chameleon-disable',function() disable('automation disabled by user') end)
mp.register_script_message('chameleon-enable',function()
    cancel(); restore(); local valid,why=capture(); enabled=valid
    if valid then last_error=nil; apply('sdr'); schedule() else warn(why) end
end)
mp.register_script_message('chameleon-refresh',function() generation=generation+1; schedule() end)
periodic=mp.add_periodic_timer(opts.poll_interval,function() check(false) end)
schedule()
