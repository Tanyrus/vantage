-- The game's own buff icons, for Replace the game's buff icons on the main page (settings.replace_game_buffs). While
-- that is in effect, the client still lays its buff window out, but its two final drawing calls are skipped, the
-- icon's and the timer's, so the game's buff icons don't show. The game's buff menu (the + menu) is kept off screen
-- with the client's own mover, which moves its frame, its icon hitboxes and its cursor together, so its cursor never
-- shows there and the mouse can't reach it. While the menu has focus, update() hands back the effect its cursor is
-- on, and ui/hud.lua draws the cursor on Vantage's own icon. Cancelling a buff stays the game's: Vantage sends
-- nothing, and the menu's keys are the client's.
--
-- Everything changed is put back when the replacement stops being in effect and when Vantage unloads.
--
-- Nothing is changed or called unless every routine is found once in the client, each one's bytes are the ones
-- this was written for, and the buff window is the client's own. Lua can't catch a crash inside the client's code,
-- so each check comes before the write or the call it guards.
local game_buffs = {};
local memory = require('core.memory');
local finder = require('core.patterns');
local address = memory.address;

-- Where each piece starts: the first bytes of six routines and the menu registry's labels around "menu    buff    ".
-- icon_paint and timer_paint are the buff window's two paint callbacks, icon_draw and timer_draw the routines their
-- final calls reach, menu_move the client's menu mover, and rebuild the buff window's list rebuild.
local patterns = {
    icon_paint = '555657E8????????8B6C24108D04408BCD8D34808B44242050C1E602E8??????',
    timer_paint = '83EC1053565768C3000000E8????????83C40485C00F8408010000E8????????',
    icon_draw = '83EC08568BF18B460885C00F84860100008B484085C9750B8B484485C90F8474',
    timer_draw = '83EC08538B5C2418555685DB750C0FBF4424185E5D5B83C408C30FBF7424180F',
    menu_move = '83EC0C668B44241453558B6C2418568BF15733FF8D5E1466896E528BCB668946',
    rebuild = '83EC1856576A028BF1E8????????8A4E6583C40484C00F94C03AC8740A8BCE88',
    registry = '6D656E75202020206D6F756E74202020????????????????????????????????????????????????????????6D656E75202020206275666620202020????????????????????????????????????????????????????????6D656E75202020206775696465303020',
};
-- The whole of each routine as this was written for it, checked where its pattern was found. ?? is an address the
-- client fills in, and in the two paint routines the five bytes of the final call, which Vantage itself changes.
local bodies = {
    icon_paint = '555657E8????????8B6C24108D04408BCD8D34808B44242050C1E602E8????????8BF885FF0F84DB0000005368C3000000BB80808080E8????????83C40485C0746A8B4C24248B948DF002000081FAFFFFFF7F74578BCFE8????????3DFF00000074492BD6B88988888883C23B8BCAF7E903D1C1FA058BC2C1E81F03D083FA0F7F2AD98588020000D80D????????E8????????B9400000002BC88BD981CB0080FFFFC1E3080BD9C1E3080BD98BCFE8????????8B4C2424888429D00200008BCFE8????????8B0D????????8BD085C9C74424240000C03F7411E8????????3C017508C74424240000403F8B4424248B4C24206A0053508B442428414051508BCA??????????5B5F5E5DC3',
    timer_paint = '83EC1053565768C3000000E8????????83C40485C00F8408010000E8????????8B7C24308B5C24208D0440578BCB8D3480C1E602E8????????85C00F84E20000008B94BBF002000081FAFFFFFF7F0F84CF0000008BC8E8????????3DFF0000000F84BD0000002BD6B88988888883C23B8BCAF7E903D1C1FA058BC2C1E81F03D08BCA83F9050F8E9800000081F9307005007C07B930700500EB0881F9100E00007C1BB8C5B3A291F7E903D1C1FA0B8BCAC1E91F03D15268????????EB2B83F93C7C20B889888888F7E903D18D4C240CC1FA058BC2C1E81F03D05268????????51EB0B5168????????8D54241452E8????????8B4C24388B54243483C40C8D44240C83C11483C20E6A01689A99593F689A99593F6880808080505152??????????83C41C5F5E5B83C410C3',
    icon_draw = '83EC08568BF18B460885C00F84860100008B484085C9750B8B484485C90F84740100008B484085C975038B4844A1????????516A008B400C508B10FF92F4000000D9442418D81D????????DFE0F6C4447B45A1????????6A026A116A008B400C508B08FF91FC0000008B15????????6A026A106A008B420C508B08FF91FC0000008B15????????6A606A188B420C508B08FF91C80000008B460833D233C957668B5024668B4826895424088D7E0CDB442408894C24086844010000D84C2420D95C2410DB44240CD84C2420DB442418D825????????DB44241CD825????????D95C24188B542418D917D9442410D8C18BC289561089462C8B44242489461C894638D95628D9C9D95E44894654894670D95E60D8442418D95648D95E648B0D????????8B410C508B10FF92300100008B0D????????6A1C576A026A05E8????????D944241CD81D????????5FDFE0F6C4447B45A1????????6A026A116A008B400C508B08FF91FC0000008B15????????6A016A106A008B420C508B08FF91FC0000008B15????????6A006A188B420C508B08FF91C80000005E83C408C21400',
    timer_draw = '83EC08538B5C2418555685DB750C0FBF4424185E5D5B83C408C30FBF7424180FBF44241C897424188944241CDB4424188A44243084C0D95C2418DB44241CD95C240C742353E8????????8944242083C404DB44241CD84C2428D80D????????D86C2418D95C24186A00E8????????8BE883C40485ED896C241C75098BC65E5D5B83C408C3578BFB83C9FF33C0F2AE8B442428F7D1493D808080808BF1897424140F85F1000000D944242CD81D????????DFE0F6C4440F8ADC000000D9442430D81D????????DFE0F6C4440F8AC7000000D944241CE8????????D94424108BF8E8????????33DB8BE885F60F8E7901000033C985DB7E088B5424248A4C13FF8B4424248A04033C858844242C747280F98575243CDA750E8B4C24208B118BB27C010000EB333CC8750E8B4424208B088BB180010000EB218B54242C81E2FF0000008D42E085C07C383D8B0000007F318B4C24208B118B348285F674240FBFC56A006A000FBFCF688080808050518BCEE8????????668B5622662B56208D7C17FF8B442414433BD80F8C64FFFFFF0FBFC75F5E5D5B83C408C333FF85F60F8EBD00000033C985FF7E048A4C1FFF8A041F3C85884424240F849700000080F985751E3CDA750B8B45008BB07C010000EB2D3CC8750B8B4D008BB180010000EB1E8B54242481E2FF0000008D42E085C07C633D8B0000007F5C8B4D008B348185F674528B5424348B4424288B4C24306A00D94424146A00528B542438505152E8????????D944243450E8????????508BCEE8????????0FBF46220FBF4E202BC14889442420DB442420D84C242CD844241CD95C241C8B442414473BF80F8C43FFFFFFD944241CE8????????8BF80FBFC75F5E5D5B83C408C3',
    menu_move = '83EC0C668B44241453558B6C2418568BF15733FF8D5E1466896E528BCB66894654897C2414897C2418E8????????3BC7894424100F848B0000008D4C2410518BCBE8????????8BF8668B076685C07523668B5724668B4722668B4E546A006A006A0152668B56525051528BCEE8????????EB34663D010075248A86990000008B4C24245051558BCFE8????????668B573A663B564C7510897C2414EB0A663D02007504897C24188B44241085C0758B8B44241485C0740E8B4C241885C9740650E8????????8B460C85C0740CC64010018B4E0C8B01FF50145F5E5D5B83C40CC20800',
    rebuild = '83EC1856576A028BF1E8????????8A4E6583C40484C00F94C03AC8740A8BCE884665E8????????53E8????????8B4E0833DB85C9895C240C7403885969B9????????552BC88BF88D6840894C2414C744241020000000668B14396681FAFFFF743A6685D274358BCB81E1FFFF000085C06689944E900200007411663917750C8B550089948EF0020000EB0BC7848EF0020000FFFFFF7F8B4C2414438B54241083C50483C7024A8954241075AAB898FDFFFF8D4E682BC6895C24108DAE68020000894C241489442418807D00007434E8????????8BFB33D281E7FFFF00007E1B8D9E9002000033C9668B0B3BC174084283C3023BD77CEF8B5C24103BD77504C64500008B4C24148B54241883C1104503D5894C241483FA207CAF8BC36A0025FFFF00008BCE50E8????????663B9E740300005D74078BCEE8????????66899E740300006685DB5B75298B4E0851B9????????E8????????3C010F85320100008B0D????????E8????????5F5E83C418C204008B5608B9????????52E8????????84C00F84AC0000008B464085C00F8EA10000008A867603000084C00F85930000008B46306681BC4690020000FFFF0F848000000033C9668B8C4690020000518BCEE8????????8BF885FF7C688D4C2414E8????????C1E7046A028D4C3768E8????????8B0D????????50E8????????8B563033C08D4C2414668B84569002000050518B0D????????E8????????6A028D4C2418E8????????8B0D????????50E8????????8D4C2414C6867603000001E8????????D9868C020000D81D????????DFE02500410000750ED905????????D8A68C020000EB06D9868C020000D80D????????D99E88020000E8????????D8AE8C020000D9968C020000D81D????????DFE0F6C4057A0AC7868C020000000020425F5E83C418C20400',
};
-- A routine another addon or plugin hooks has a jump written over its first bytes. Its pattern starts on those
-- bytes, so it then finds nothing, though the rest of the routine is still there. So the mover has a second pattern:
-- the 48 bytes of it from 17 on, past anything a hook writes. That one is looked for only when the mover's own
-- pattern finds nothing. When the mover starts with a jump, Vantage calls it through the hook, which runs the mover.
local LATER = { menu_move = 'menu_move_later' };
local LATER_FROM, JUMP = 17, 0xE9;
patterns.menu_move_later = bodies.menu_move:sub(LATER_FROM * 2 + 1, (LATER_FROM + 48) * 2);
local ORDER = { 'icon_paint', 'timer_paint', 'icon_draw', 'timer_draw', 'menu_move', 'rebuild', 'registry' };
local LABELS = { icon_paint = 'buff icon painting', timer_paint = 'buff timer painting', icon_draw = 'icon drawing',
    timer_draw = 'timer drawing', menu_move = 'menu mover', rebuild = 'buff list rebuild', registry = 'menu registry' };
-- The one match inside the client module.
local RULE = { unique = true, within = true };

-- Each paint routine's final call, from the routine's start.
local ICON_CALL, TIMER_CALL = 0x100, 0x11B;
-- The icon draw takes five arguments and clears them itself (it ends in ret 0x14), so in its place the stack pointer
-- steps over them: lea esp, [esp + 0x14], then a nop. The timer draw leaves its arguments to its caller, so its call
-- is left out with five nops.
local ICON_SKIP, TIMER_SKIP = string.char(0x8D, 0x64, 0x24, 0x14, 0x90), string.rep(string.char(0x90), 5);
-- The registry names the slot that holds the buff window, 0x4C from its first label. The icon paint names the same
-- slot at 0xC7, and the rebuild names the client's focus manager at 0x14D. The buff window's vtable holds the rebuild
-- at 0x60.
local SLOT, PAINT_SLOT, MANAGER, VTABLE_REBUILD = 0x4C, 0xC7, 0x14D, 0x60;
-- "menu    buff    ", the buff window's name in its header.
local NAME = { 0x756E656D, 0x20202020, 0x66667562, 0x20202020 };
-- Where a held menu sits. No screen reaches it.
local OFF = -16000;

-- platform is how the client is read, written and called, nil where that can't be done. found holds what look()
-- found, false when this client can't be used, and refusal says why. on is whether the game's icons are replaced
-- now. stopped is set once the replacement could not start or had to stop, and problem says why until it is out of
-- effect again. held is the menu Vantage moved off screen and where it was. moved and returned count the moves, for
-- /vg report. pick is what update() hands back.
local platform, platform_tried;
local found, refusal, problem;
local on, stopped, held = false, nil, nil;
local moved, returned = 0, 0;
local pick = {};

-- The real client: page checks from core/memory.lua, the finder, and kernel32 for writing code. The tests set their
-- own, so no test ever writes or calls anything in the process it runs in.
local function load_platform()
    if platform_tried then return platform; end
    platform_tried = true;
    if VANTAGE_TEST_MODE then return nil; end
    local ok, made = pcall(function()
        local ffi = require('ffi');
        if ffi.os ~= 'Windows' or not ffi.abi('32bit') or not ashita or not ashita.memory then return nil; end
        pcall(ffi.cdef, 'int __stdcall VirtualProtect(void*, size_t, unsigned long, unsigned long*);');
        pcall(ffi.cdef, 'int __stdcall FlushInstructionCache(void*, const void*, size_t);');
        pcall(ffi.cdef, 'void* __stdcall GetCurrentProcess(void);');
        local pages = memory.pages();
        local old, ignored = ffi.new('unsigned long[1]'), ffi.new('unsigned long[1]');
        return {
            valid = pages.valid, readable = pages.readable,
            find = function(name) return finder.find('game_buffs', name, patterns[name], RULE); end,
            bytes = function(at, size) return ffi.string(ffi.cast('const char*', at), size); end,
            read8 = ashita.memory.read_uint8, read16 = ashita.memory.read_uint16, read32 = ashita.memory.read_uint32,
            -- Makes the bytes writable, writes them, puts the protection back and tells the processor the code changed.
            -- True only when the bytes read back as written.
            write_code = function(at, bytes)
                local where = ffi.cast('void*', at);
                if ffi.C.VirtualProtect(where, #bytes, 0x40, old) == 0 then return false; end
                ffi.copy(where, bytes, #bytes);
                local restored = ffi.C.VirtualProtect(where, #bytes, old[0], ignored) ~= 0;
                local flushed = ffi.C.FlushInstructionCache(ffi.C.GetCurrentProcess(), where, #bytes) ~= 0;
                return restored and flushed and ffi.string(ffi.cast('const char*', at), #bytes) == bytes;
            end,
            -- The client's menu mover: this in ecx, then x and y, cleared by the mover itself.
            move = function(routine, menu, x, y)
                ffi.cast('void (__thiscall *)(void*, int, int)', routine)(ffi.cast('void*', menu), x, y);
            end,
        };
    end);
    platform = ok and made or nil;
    return platform;
end

-- Every read checks its pages first, so memory the client freed reads as nothing.
local function valid(at, size, writable)
    if not address(at) then return false; end
    local ok, good = pcall(platform.valid, at, size, writable == true);
    return ok and good == true;
end
local function read(kind, at, size)
    if not valid(at, size) then return nil; end
    local ok, value = pcall(platform[kind], at);
    if ok and type(value) == 'number' then return value; end
end
local function read8(at) return read('read8', at, 1); end
local function read32(at) return read('read32', at, 4); end
-- A 16 bit value as the signed number a menu's place is.
local function place(at)
    local value = read('read16', at, 2);
    if value == nil then return nil; end
    return value >= 32768 and value - 65536 or value;
end
local function code(at, size)
    if not address(at) then return nil; end
    local ok, good = pcall(platform.readable, at, size);
    if not ok or good ~= true then return nil; end
    local read_ok, text = pcall(platform.bytes, at, size);
    if read_ok and type(text) == 'string' and #text == size then return text; end
end

-- Whether the bytes at an address are a body's, ?? aside.
local function matches(at, body)
    local size = #body / 2;
    local text = code(at, size);
    if not text then return false; end
    for index = 1, size do
        local pair = body:sub(index * 2 - 1, index * 2);
        if pair ~= '??' and tonumber(pair, 16) ~= text:byte(index) then return false; end
    end
    return true;
end

-- The five bytes of a call from at to a routine.
local function call(at, to)
    local value = (to - at - 5) % 4294967296;
    local bytes = { 0xE8 };
    for index = 2, 5 do bytes[index] = value % 256; value = math.floor(value / 256); end
    return string.char(unpack(bytes));
end

-- Finds everything once. found.sites are the two calls with the bytes each holds unchanged and skipped.
local function look()
    if found ~= nil then return found; end
    found = false;
    if not load_platform() then
        refusal = 'Vantage can\'t reach this game client\'s drawing code, so the game\'s buff icons stay as they are.';
        return false;
    end
    local ok, result, why = pcall(function()
        local at, hooked = {}, {};
        for _, name in ipairs(ORDER) do
            local where, reason = platform.find(name);
            if not where then
                reason = reason or 'is missing';
                local later = LATER[name] and reason == 'is missing' and platform.find(LATER[name]);
                if later and read8(later - LATER_FROM) == JUMP then
                    where, hooked[name] = later - LATER_FROM, true;
                elseif later then
                    return nil, ('Something else in the game, such as another addon or plugin, has changed this game client\'s %s, so the game\'s buff icons stay as they are.'):format(LABELS[name]);
                else
                    return nil, ('This game client\'s %s %s, so the game\'s buff icons stay as they are.'):format(LABELS[name], reason);
                end
            end
            at[name] = where;
        end
        for _, name in ipairs(ORDER) do
            local from = hooked[name] and LATER_FROM or 0;
            if bodies[name] and not matches(at[name] + from, bodies[name]:sub(from * 2 + 1)) then
                return nil, ('This game client\'s %s is not the code Vantage knows, so the game\'s buff icons stay as they are.'):format(LABELS[name]);
            end
        end
        local slot, manager = read32(at.registry + SLOT), read32(at.rebuild + MANAGER);
        if not address(slot) or slot ~= read32(at.icon_paint + PAINT_SLOT) or not address(manager) or not valid(slot, 4)
            or not valid(manager, 0x60) then
            return nil, 'This game client\'s buff window was not found where Vantage looks, so the game\'s buff icons stay as they are.';
        end
        local sites = {
            { at = at.icon_paint + ICON_CALL, original = call(at.icon_paint + ICON_CALL, at.icon_draw), skip = ICON_SKIP },
            { at = at.timer_paint + TIMER_CALL, original = call(at.timer_paint + TIMER_CALL, at.timer_draw), skip = TIMER_SKIP },
        };
        for _, site in ipairs(sites) do
            local now = code(site.at, 5);
            if now ~= site.original and now ~= site.skip then
                return nil, 'Something else already changed the game\'s buff drawing, so Vantage leaves it alone.';
            end
        end
        return { sites = sites, slot = slot, manager = manager, rebuild = at.rebuild, move = at.menu_move };
    end);
    if ok and result then found = result;
    else refusal = ok and why or 'Vantage could not check this game client\'s buff drawing, so the game\'s buff icons stay as they are.'; end
    return found;
end

-- The game's buff window as the client holds it now: its container and its menu, or nothing while there is none
-- (the title screen, a zone change) or while it isn't the one this was written for.
local function window()
    local container = read32(found.slot);
    if not address(container) then return nil; end
    local vtable = read32(container);
    if not address(vtable) or read32(vtable + VTABLE_REBUILD) ~= found.rebuild then return nil; end
    local menu = read32(container + 8);
    if not address(menu) or read32(menu + 0x0C) ~= container then return nil; end
    local header = read32(menu + 4);
    if not address(header) then return nil; end
    for index = 1, 4 do
        if read32(header + 0x46 + (index - 1) * 4) ~= NAME[index] then return nil; end
    end
    return container, menu;
end

-- Whether the menu has the client's main focus and is neither closing (state 14) nor deleted.
local function focused(menu)
    local state = read32(menu + 0x10);
    return read8(menu + 0x6A) == 1 and read32(found.manager + 0x54) == menu and read8(menu + 0x70) == 0
        and state ~= nil and state ~= 14;
end

-- Whether everything the mover writes can be written: the menu, its container, its scrollbar, and each frame, icon
-- and cursor object on the menu's list.
local function movable(container, menu)
    if not valid(menu, 0x9C, true) or not valid(container, 0x378, true) then return false; end
    local scrollbar = read32(menu + 0x88);
    if scrollbar == nil or scrollbar ~= 0 and not valid(scrollbar, 0x2C, true) then return false; end
    -- A list longer than any menu's, as one that loops is, is not walked on.
    local node, count = read32(menu + 0x14), 0;
    while node and node ~= 0 do
        if count >= 128 then return false; end
        count = count + 1;
        local skipped = read8(node + 0x14);
        if skipped == nil then return false; end
        if skipped == 0 then
            local object = read32(node + 0x10);
            local kind = object and read('read16', object, 2);
            local size = kind == 0 and 0x50 or kind == 1 and 0x60 or kind == 2 and 0x34;
            if not size or not valid(object, size, true) then return false; end
        end
        node = read32(node);
    end
    return node == 0 and count > 0;
end

-- Moves the menu with the client's mover, and says whether it then sits where asked.
local function move(container, menu, x, y)
    if not movable(container, menu) then return false; end
    local ok = pcall(platform.move, found.move, menu, x, y);
    return ok and place(menu + 0x52) == x and place(menu + 0x54) == y;
end

-- Puts back whatever is changed: the menu where it was, when it is still the one Vantage moved and still off
-- screen, and the two calls. False when something could not be put back.
local function put_back()
    local clean = true;
    if not found then held = nil; return clean; end
    if held then
        local container, menu = window();
        if container == held.container and menu == held.menu and place(menu + 0x52) == OFF and place(menu + 0x54) == OFF then
            if move(container, menu, held.x, held.y) then returned = returned + 1; else clean = false; end
        end
        held = nil;
    end
    for _, site in ipairs(found.sites) do
        local now = code(site.at, 5);
        if now == site.skip then
            local ok, written = pcall(platform.write_code, site.at, site.original);
            if not ok or written ~= true then clean = false; end
        elseif now ~= site.original then clean = false; end
    end
    return clean;
end

local PUT_BACK_FAILED = 'Vantage could not put the game\'s buff drawing back. Restart the game to get its buff icons back.';

-- Skips the two calls. True, or false and why not, with whatever it wrote put back.
local function start()
    if not look() then return false, refusal; end
    for _, site in ipairs(found.sites) do
        local now = code(site.at, 5);
        local ok, written = true, true;
        if now == site.original then ok, written = pcall(platform.write_code, site.at, site.skip);
        elseif now ~= site.skip then ok = false; end
        if not ok or written ~= true then
            local clean = put_back();
            return false, clean and 'Vantage could not change the game\'s buff drawing, so the game\'s buff icons stay as they are.' or PUT_BACK_FAILED;
        end
    end
    return true;
end

-- What the + menu's cursor is on while the menu has focus, as the client lists it: how many effects it lists at
-- 0x40, the cursor's place among them at 0x30, each one's effect from 0x290, and from 0x2D0 whether the client lets
-- it be cancelled. The same table each time.
local function picked(container, menu)
    if not focused(menu) then return nil; end
    local count, index = read32(container + 0x40), read32(container + 0x30);
    if not count or not index or count < 1 or count > 32 or index >= count then return nil; end
    local effect = read('read16', container + 0x290 + index * 2, 2);
    if not effect or effect < 1 or effect > 1023 then return nil; end
    pick.effect, pick.can_cancel = effect, read8(container + 0x2D0 + index) == 1;
    return pick;
end

-- Each Present. want is whether the settings ask for the game's buff icons to be replaced now. While they are, the
-- game's buff menu is kept off screen. Returns what the + menu's cursor is on while the menu has focus, as
-- { effect, can_cancel }, and a line to say when the replacement could not start, had to stop or could not be put
-- back. After it could not start or had to stop, it stays off until want has been false once.
function game_buffs.update(want)
    if not want then
        stopped, problem = nil, nil;
        if not on then return nil; end
        on = false;
        if not put_back() then problem = PUT_BACK_FAILED; return nil, PUT_BACK_FAILED; end
        return nil;
    end
    if stopped then return nil; end
    if not on then
        local ok, why = start();
        if not ok then stopped, problem = true, why; return nil, why; end
        on, problem = true, nil;
    end
    local container, menu = window();
    -- A menu Vantage moved that the client has since replaced is never put back into the new one.
    if held and (container ~= held.container or menu ~= held.menu) then held = nil; end
    if not container then return nil; end
    local x, y = place(menu + 0x52), place(menu + 0x54);
    if x == nil or y == nil then return nil; end
    if x ~= OFF or y ~= OFF then
        -- Wherever the client last put it is where it goes back to.
        if not move(container, menu, OFF, OFF) then
            local clean = put_back();
            on, stopped = false, true;
            problem = 'Vantage could not move the game\'s buff menu off screen, so the game draws its own buff icons again.'
                .. (clean and '' or ' ' .. PUT_BACK_FAILED);
            return nil, problem;
        end
        held, moved = { container = container, menu = menu, x = x, y = y }, moved + 1;
    end
    return picked(container, menu);
end

-- Unload: everything put back. False and a line to say when something could not be.
function game_buffs.release()
    local clean = put_back();
    on, stopped = false, nil;
    if not clean then return false, PUT_BACK_FAILED; end
    return true;
end

-- Why the game's icons aren't replaced while the settings ask for it, for the main page. nil while they are.
function game_buffs.problem() return problem; end

-- For /vg report: whether the game's icons are replaced now, why not when they should be, whether the game's menu
-- is off screen now, and how often it was moved off and back.
function game_buffs.status()
    return { on = on, problem = problem, held = held ~= nil, moved = moved, returned = returned };
end

if VANTAGE_TEST_MODE then
    -- A platform of the test's own in place of the client: { valid, readable, find, bytes, read8, read16, read32,
    -- write_code, move }. nil is a client that can't be reached.
    function game_buffs._set_platform(value)
        platform, platform_tried = value, true;
        found, refusal, problem, on, stopped, held, moved, returned = nil, nil, nil, false, nil, nil, 0, 0;
    end
    game_buffs._patterns, game_buffs._bodies = patterns, bodies;
    game_buffs._ICON_SKIP, game_buffs._TIMER_SKIP, game_buffs._OFF = ICON_SKIP, TIMER_SKIP, OFF;
end

return game_buffs;
