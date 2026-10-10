-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (c) 2026 mpv-chameleon contributors
-- The real script runs against a small mpv boundary double; no video hardware.
local passed, failed = 0, 0
local function eq(a, b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
local function env(overrides, options)
    local e = {now=0, timers={}, events={}, observers={}, messages={}, hooks={}, requests={}, writes={}, logs={}, aborted={}}
    e.props = {['video-params']={gamma='pq',primaries='bt.2020'}, ['platform']='darwin', ['target-prim']='auto', ['target-trc']='auto',
        ['target-gamut']='auto', ['target-peak']='auto', ['tone-mapping']='auto',
        ['target-colorspace-hint']='auto', ['target-colorspace-hint-mode']='target',
        ['target-colorspace-hint-strict']='yes', ['icc-profile']='', ['icc-profile-auto']='no',
        ['inverse-tone-mapping']='no', ['current-vo']='gpu-next', ['current-gpu-context']='macvk',
        ['vo-configured']=true, ['display-names']={'Panel (123)'}, ['options/vo']='gpu-next',
        ['options/gpu-context']='macvk', ['options/gpu-api']='vulkan'}
    for k,v in pairs(overrides or {}) do e.props[k]=v end
    local mp = {msg={}}
    for _,level in ipairs({'info','warn','error','verbose','debug'}) do
        mp.msg[level]=function(s) e.logs[#e.logs+1]=level..':'..s end
    end
    mp.get_property = function(k, default) local v=e.props[k]; if v==nil then return default end; return v end
    mp.get_property_native=mp.get_property
    mp.set_property=function(k,v)
        if e.fail_property==k then return nil,'unavailable' end
        e.writes[#e.writes+1]={k,v}; e.props[k]=v; return true
    end
    mp.set_property_native=mp.set_property
    mp.get_script_name=function() return 'chameleon' end
    mp.get_time=function() return e.now end
    mp.command_native=function(t) assert(t[1]=='expand-path'); return '/config/'..t[2]:gsub('^~~/','') end
    mp.command_native_async=function(t, cb)
        assert(t.name=='subprocess' and t.args[2]=='--display')
        assert(t.capture_size == 262144 and t.max_size == nil, 'mpv subprocess requires capture_size')
        e.requests[#e.requests+1]={args=t.args, cb=cb}; return #e.requests
    end
    mp.abort_async_command=function(id) e.aborted[id]=true end
    local function timer(seconds, fn, periodic)
        local t={at=e.now+seconds, fn=fn, seconds=seconds, periodic=periodic, active=true}
        function t:kill() self.active=false end
        function t:resume() self.active=true; self.at=e.now+self.seconds end
        e.timers[#e.timers+1]=t; return t
    end
    mp.add_timeout=function(s,fn) return timer(s,fn,false) end
    mp.add_periodic_timer=function(s,fn) return timer(s,fn,true) end
    mp.observe_property=function(n,_,fn) e.observers[n]=fn end
    mp.register_event=function(n,fn) e.events[n]=fn end
    mp.register_script_message=function(n,fn) e.messages[n]=fn end
    mp.add_hook=function(n,_,fn) e.hooks[n]=fn end
    package.loaded.mp=mp
    package.loaded['mp.utils']={parse_json=function(s) return e.json[s] end,
        file_info=function(p) if e.legacy and p:match('auto%-hdr%.lua$') then return {} end end}
    package.loaded['mp.options']={read_options=function(o) for k,v in pairs(options or {}) do o[k]=v end end}
    e.json={}
    function e:advance(seconds)
        local stop=self.now+seconds
        for _=1,1000 do
            local next_timer
            for _,t in ipairs(self.timers) do
                if t.active and t.at<=stop and (not next_timer or t.at<next_timer.at) then next_timer=t end
            end
            if not next_timer then break end
            self.now=next_timer.at; next_timer.active=next_timer.periodic
            if next_timer.periodic then next_timer.at=self.now+next_timer.seconds end
            next_timer.fn()
        end
        self.now=stop
    end
    function e:display(name)
        self.props['display-names']=name and {name} or {}
        if self.observers['display-names'] then self.observers['display-names']() end
    end
    function e:reply(id, potential, status)
        local token='response'..id
        self.json[token]={schema_version=1, displays={{id=7,name='Panel',potential_edr=potential}},
            selection={status=status or 'exact',display_id=7}}
        self.requests[id].cb(true,{status=0,stdout=token},nil)
    end
    function e:load() dofile('scripts/chameleon.lua'); self:advance(0.2) end
    return e
end
local function test(name, fn)
    local ok, err=pcall(fn)
    if ok then passed=passed+1; print('ok '..name) else failed=failed+1; print('FAIL '..name..': '..err) end
end

test('startup applies SDR before helper returns',function()
    local e=env(); e:load(); eq(e.props['target-trc'],'srgb'); eq(e.props['target-prim'],'bt.709')
    eq(e.props['tone-mapping'],'bt.2390'); eq(#e.requests,1)
end)
test('HDR restores customized color settings and SDR clears them',function()
    local e=env({['target-prim']='display-p3',['tone-mapping']='spline',['target-peak']='600',['target-gamut']='dci-p3'})
    e:load(); eq(e.props['target-peak'],'auto'); e:reply(1,16)
    eq(e.props['target-prim'],'display-p3'); eq(e.props['tone-mapping'],'spline'); eq(e.props['target-peak'],'600')
    e:display('Other (456)'); e:advance(.2); e:reply(2,1)
    eq(e.props['target-trc'],'srgb'); eq(e.props['target-gamut'],'auto')
    e:display('Panel (123)'); e:advance(.2); e:reply(3,16); eq(e.props['target-gamut'],'dci-p3')
end)
test('same mode and repeated observations do not rewrite or spawn',function()
    local e=env(); e:load(); e:reply(1,16); local writes=#e.writes
    for _=1,10 do e:display('Panel (123)') end
    e:advance(1); eq(#e.requests,1); eq(#e.writes,writes)
    e:advance(16); e:reply(2,16); eq(#e.writes,writes)
end)
test('rapid A B A rejects stale callback and queries newest once',function()
    local e=env(); e:load(); e:display('Other (456)'); e:display('Panel (123)'); e:advance(.2)
    eq(#e.requests,1); e:reply(1,16); eq(e.props['target-trc'],'srgb')
    e:advance(.2); eq(#e.requests,2); e:reply(2,16); eq(e.props['target-colorspace-hint'],'yes')
    eq(e.requests[2].args[3],'Panel (123)')
end)
for _,status in ipairs({'ambiguous','unknown'}) do
    test(status..' falls back from HDR',function()
        local e=env(); e:load(); e:reply(1,16); e:advance(16); e:reply(2,16,status)
        eq(e.props['target-trc'],'srgb')
    end)
end
for _,value in ipairs({-1,0,0.5,math.huge,'16',false}) do
    test('invalid EDR '..tostring(value),function()
        local e=env(); e:load(); e:reply(1,value); eq(e.props['target-trc'],'srgb')
    end)
end
test('empty displays never launches helper or enables HDR',function()
    local e=env({['display-names']={}}); e:load(); eq(#e.requests,0); eq(e.props['target-trc'],'srgb')
end)
test('malformed JSON falls back and later recovers',function()
    local e=env(); e:load(); e:reply(1,16); e:advance(16)
    e.requests[2].cb(true,{status=0,stdout='bad'},nil); eq(e.props['target-trc'],'srgb')
    e:advance(16); e:reply(3,16); eq(e.props['target-trc'],'auto')
end)
test('subprocess failure falls back without flooding',function()
    local e=env(); e:load(); e:reply(1,16)
    for _=1,3 do e:advance(16); e.requests[#e.requests].cb(false,{status=127},'failed') end
    eq(e.props['target-trc'],'srgb')
    local warnings=0; for _,s in ipairs(e.logs) do if s:match('warn:') then warnings=warnings+1 end end
    eq(warnings,1)
end)
test('timeout aborts helper and ignores its late result',function()
    local e=env(); e:load(); e:advance(6); eq(e.aborted[1],true)
    e:reply(1,16); eq(e.props['target-trc'],'srgb')
    e:advance(16); eq(#e.requests,2)
end)
test('shutdown restores only owned properties and cancels pending',function()
    local e=env(); e:load(); e.props['tone-mapping']='mobius'; e.events.shutdown()
    eq(e.props['tone-mapping'],'mobius'); eq(e.props['target-trc'],'auto'); eq(e.aborted[1],true)
    e:reply(1,16); eq(e.props['target-colorspace-hint'],'auto')
end)
test('runtime profile conflict disables automation and preserves edit',function()
    local e=env(); e:load(); e:reply(1,16); e.props['target-trc']='gamma2.4'; e:advance(16)
    e:reply(2,1); eq(e.props['target-trc'],'gamma2.4'); eq(e.props['target-colorspace-hint'],'auto')
end)
test('unsupported runtime renderer leaves original settings',function()
    local e=env({['current-gpu-context']='displayvk'}); e:load(); eq(e.props['target-trc'],'auto'); eq(#e.requests,0)
end)
for _,p in ipairs({'icc-profile-auto','inverse-tone-mapping'}) do
    test('rejects conflicting '..p,function()
        local e=env({[p]='yes'}); e:load(); eq(e.props['target-trc'],'auto'); eq(#e.requests,0)
    end)
end
test('rejects strict=no',function() local e=env({['target-colorspace-hint-strict']='no'}); e:load(); eq(#e.requests,0) end)
test('missing property refuses to start',function()
    local e=env(); e.props['target-peak']=nil; e:load(); eq(e.props['target-trc'],'auto'); eq(#e.requests,0)
end)
test('legacy autoload refuses to compete',function() local e=env(); e.legacy=true; e:load(); eq(#e.requests,0) end)
test('on_load forces safe mode and lifecycle resumes',function()
    local e=env(); e:load(); e:reply(1,16); e.hooks.on_load(); eq(e.props['target-trc'],'srgb')
    e.events['file-loaded'](); e:advance(.2); eq(#e.requests,2)
end)
test('idle vo cancels helper and pauses periodic queries',function()
    local e=env(); e:load(); e.props['vo-configured']=false; e.observers['vo-configured']()
    e:advance(60); eq(#e.requests,1); eq(e.aborted[1],true)
end)
test('property failure never reports successful HDR',function()
    local e=env(); e:load(); e.fail_property='target-trc'; e:reply(1,16)
    eq(e.props['target-colorspace-hint'],'no')
    for _,s in ipairs(e.logs) do assert(not s:match('mode: hdr')) end
end)
test('wrong schema or duplicate selected ID cannot enable HDR',function()
    local e=env(); e:load(); e.json.bad={schema_version=2,displays={},selection={status='exact',display_id=7}}
    e.requests[1].cb(true,{status=0,stdout='bad'}); eq(e.props['target-trc'],'srgb')
end)
test('SDR on HDR-capable display stays SDR even with customized HDR targets',function()
    local e=env({['video-params']={gamma='bt.1886',primaries='bt.709'},['target-trc']='pq',['target-peak']='1000',['tone-mapping']='spline'})
    e:load(); e:reply(1,16); eq(e.props['target-trc'],'srgb'); eq(e.props['target-peak'],'auto'); eq(e.props['tone-mapping'],'spline')
    e:display('Other (456)'); e:advance(.2); e:reply(2,1); eq(e.props['target-trc'],'srgb')
    e:display('Panel (123)'); e:advance(.2); e:reply(3,16); eq(e.props['target-trc'],'srgb')
    for _,s in ipairs(e.logs) do assert(not s:match('mode: hdr')) end
end)
test('same-instance HDR SDR HDR file change tracks source independently',function()
    local e=env(); e:load(); e:reply(1,16); eq(e.props['target-trc'],'auto')
    e.props['video-params']={gamma='bt.1886',primaries='bt.709'}; e.observers['video-params']()
    eq(e.props['target-trc'],'srgb'); e:advance(.2); e:reply(2,16); eq(e.props['target-trc'],'srgb')
    e.props['video-params']={gamma='pq',primaries='bt.2020'}; e.observers['video-params']()
    e:advance(.2); e:reply(3,16); eq(e.props['target-trc'],'auto')
end)
for _,params in ipairs({{}, {gamma='pq'}, {gamma='pq',primaries='bt.709'}, {gamma='hlg',primaries='bt.2020'}}) do
    test('unknown ambiguous or HLG source uses conservative SDR',function()
        local e=env({['video-params']=params}); e:load(); e:reply(1,16); eq(e.props['target-trc'],'srgb')
    end)
end
test('stale request timeout promptly queries newest display despite long refresh',function()
    local e=env(nil,{refresh_interval=300}); e:load(); e:display('Other (456)')
    e:advance(5.2); eq(#e.requests,2); eq(e.requests[2].args[3],'Other (456)')
    e:reply(1,16); eq(e.props['target-trc'],'srgb')
    e:reply(2,1); eq(e.props['target-trc'],'srgb')
end)
test('default explicitly signals an SDR target',function()
    local e=env({['video-params']={gamma='bt.1886',primaries='bt.709'}}); e:load(); e:reply(1,16)
    eq(e.props['target-colorspace-hint'],'yes'); eq(e.props['target-colorspace-hint-mode'],'target')
    eq(e.props['target-trc'],'srgb')
end)
print(string.format('Lua: %d passed, %d failed',passed,failed))
os.exit(failed==0 and 0 or 1)
