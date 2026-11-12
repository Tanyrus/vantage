-- Replace the game's buff icons (core/game_buffs.lua), over a made-up client. While it is in effect the buff window's
-- two final drawing calls are skipped, the game's + menu is kept off screen, and update() hands back what the menu's
-- cursor is on while the menu has focus. Out of effect, at unload, and after a move that fails, everything is as it
-- was. Nothing is written or called unless every routine is found once, its bytes are the ones this was written for,
-- and the buff window is the client's own.
local game_buffs = require('core.game_buffs');
local OFF = game_buffs._OFF;
assert(OFF == -16000, 'Off screen is where no screen reaches.');
local CANT_REACH = 'Vantage can\'t reach this game client\'s drawing code, so the game\'s buff icons stay as they are.';
local CANT_MOVE = 'Vantage could not move the game\'s buff menu off screen, so the game draws its own buff icons again.';
local CANT_PUT_BACK = 'Vantage could not put the game\'s buff drawing back. Restart the game to get its buff icons back.';

-- In the tests the real client is never reached: with no platform set, nothing is replaced, and nothing asks ffi for
-- anything.
do
    local asked, real = 0, package.loaded.ffi;
    package.loaded.ffi = setmetatable({}, { __index = function(_, key) asked = asked + 1; error('ffi.' .. tostring(key) .. ' was asked for', 0); end });
    local pick, reason = game_buffs.update(true);
    package.loaded.ffi = real;
    assert(pick == nil and reason == CANT_REACH and asked == 0, ('A test never builds the real platform: %s, %d asked'):format(tostring(reason), asked));
end

-- Memory as bytes by address. Only what a test maps can be read, and only the heap can be written by the mover's rule.
local mem, heap = {}, { from = 0x20000000, to = 0x20010000 };
local function put(at, bytes) for index = 1, #bytes do mem[at + index - 1] = bytes:byte(index); end end
local function get(at, size)
    local out = {};
    for index = 0, size - 1 do
        local byte = mem[at + index];
        if byte == nil then return nil; end
        out[index + 1] = string.char(byte);
    end
    return table.concat(out);
end
local function le(value, size)
    value = value % 2 ^ (size * 8);
    local out = {};
    for index = 1, size do out[index] = string.char(value % 256); value = math.floor(value / 256); end
    return table.concat(out);
end
local function number(at, size)
    local bytes = get(at, size);
    if not bytes then return nil; end
    local value = 0;
    for index = size, 1, -1 do value = value * 256 + bytes:byte(index); end
    return value;
end
local function plant(at, pattern)
    put(at, (pattern:gsub('..', function(pair) return string.char(pair == '??' and 0 or tonumber(pair, 16)); end)));
end
local function call(at, to) return string.char(0xE8) .. le(to - at - 5, 4); end

local CODE, HEAP = 0x10000000, heap.from;
local where = { icon_paint = CODE + 0x1000, timer_paint = CODE + 0x2000, icon_draw = CODE + 0x3000, timer_draw = CODE + 0x4000,
    menu_move = CODE + 0x5000, rebuild = CODE + 0x6000, registry = CODE + 0x8000 };
local ICON, TIMER = where.icon_paint + 0x100, where.timer_paint + 0x11B;
local SLOT, MANAGER, VTABLE = CODE + 0x9000, CODE + 0x9100, CODE + 0xA000;
local container, menu, header = HEAP, HEAP + 0x1000, HEAP + 0x2000;
local missing, calls;

-- What the + menu lists, as the client keeps it: how many, the cursor's place, each effect, and which can be cancelled.
local function listed(effects, index, fixed)
    put(container + 0x40, le(#effects, 4));
    put(container + 0x30, le(index, 4));
    for place, effect in ipairs(effects) do
        put(container + 0x290 + (place - 1) * 2, le(effect, 2));
        put(container + 0x2D0 + place - 1, fixed and fixed[effect] and '\0' or '\1');
    end
end

-- A whole client with the buff window at 1700, 20, three objects on its list (a frame, an icon and a cursor), and
-- Protect, Shell and Poison listed with the cursor on Protect. Poison can't be cancelled.
local function client()
    mem, missing, calls = {}, {}, { writes = {}, moves = {} };
    for name, body in pairs(game_buffs._bodies) do plant(where[name], body); end
    plant(where.registry, game_buffs._patterns.registry);
    put(ICON, call(ICON, where.icon_draw));
    put(TIMER, call(TIMER, where.timer_draw));
    put(where.registry + 0x4C, le(SLOT, 4));
    put(where.icon_paint + 0xC7, le(SLOT, 4));
    put(where.rebuild + 0x14D, le(MANAGER, 4));
    put(SLOT, le(container, 4));
    put(MANAGER, string.rep('\0', 0x60));
    put(VTABLE, string.rep('\0', 0x80));
    put(VTABLE + 0x60, le(where.rebuild, 4));
    put(container, string.rep('\0', 0x378));
    put(container, le(VTABLE, 4));
    put(container + 8, le(menu, 4));
    put(menu, string.rep('\0', 0x9C));
    put(menu + 4, le(header, 4));
    put(menu + 0x0C, le(container, 4));
    put(menu + 0x10, le(3, 4));
    put(menu + 0x52, le(1700, 2) .. le(20, 2));
    put(menu + 0x6A, '\1');
    put(header, string.rep('\0', 0x60));
    put(header + 0x46, 'menu    buff    ');
    local node = HEAP + 0x3000;
    put(menu + 0x14, le(node, 4));
    for index, kind in ipairs({ 0, 1, 2 }) do
        local object = node + 0x40;
        put(node, string.rep('\0', 0x18));
        put(node, le(index < 3 and node + 0x100 or 0, 4));
        put(node + 0x10, le(object, 4));
        put(object, string.rep('\0', kind == 0 and 0x50 or kind == 1 and 0x60 or 0x34));
        put(object, le(kind, 2));
        node = node + 0x100;
    end
    listed({ 40, 41, 3 }, 0, { [3] = true });
end

local finds = 0;
local platform = {
    valid = function(at, size, writable)
        if get(at, size) == nil then return false; end
        return not writable or (at >= heap.from and at + size <= heap.to);
    end,
    readable = function(at, size) return get(at, size) ~= nil; end,
    find = function(name)
        finds = finds + 1;
        if missing[name] then return nil, missing[name]; end
        return where[name];
    end,
    bytes = get,
    read8 = function(at) return number(at, 1); end,
    read16 = function(at) return number(at, 2); end,
    read32 = function(at) return number(at, 4); end,
    write_code = function(at, bytes)
        calls.writes[#calls.writes + 1] = { at = at, bytes = bytes };
        if calls.fail_write == #calls.writes then return false; end
        put(at, bytes);
        return true;
    end,
    move = function(routine, target, x, y)
        calls.moves[#calls.moves + 1] = { routine = routine, menu = target, x = x, y = y };
        if not calls.stuck then put(target + 0x52, le(x, 2) .. le(y, 2)); end
    end,
};
local function fresh()
    client();
    finds = 0;
    game_buffs._set_platform(platform);
end
local function focus(on) put(MANAGER + 0x54, le(on and menu or 0, 4)); end
local function sits(x, y, which)
    local at_x, at_y = number((which or menu) + 0x52, 2), number((which or menu) + 0x54, 2);
    return at_x == x % 65536 and at_y == y % 65536;
end
local function calls_are(kind)
    if kind == 'skipped' then return get(ICON, 5) == game_buffs._ICON_SKIP and get(TIMER, 5) == game_buffs._TIMER_SKIP; end
    return get(ICON, 5) == call(ICON, where.icon_draw) and get(TIMER, 5) == call(TIMER, where.timer_draw);
end
local function snapshot() local copy = {}; for at, byte in pairs(mem) do copy[at] = byte; end return copy; end
local function same(before)
    for at, byte in pairs(before) do if mem[at] ~= byte then return false, at; end end
    for at in pairs(mem) do if before[at] == nil then return false, at; end end
    return true;
end
-- One Present with the replacement asked for, and one without.
local function on() return game_buffs.update(true); end
local function off() return game_buffs.update(false); end

-- Out of effect it looks for nothing.
fresh();
local pick, notice = off();
assert(pick == nil and notice == nil and finds == 0 and game_buffs.status().on == false, 'Out of effect, nothing is looked for.');
assert(game_buffs.release() == true and finds == 0 and #calls.writes == 0, 'An unload that never replaced anything changes nothing.');

-- In effect: the two calls are skipped, and the game's menu goes off screen at once, focus or not.
local before = snapshot();
pick, notice = on();
assert(pick == nil and notice == nil and game_buffs.status().on and game_buffs.problem() == nil, 'The replacement starts: ' .. tostring(notice));
assert(finds == 7, 'Each of the seven pieces is looked for once: ' .. finds);
assert(calls_are('skipped'), 'Both final drawing calls are skipped.');
assert(#calls.writes == 2 and calls.writes[1].at == ICON and calls.writes[2].at == TIMER, 'Only the two calls are written.');
assert(#calls.moves == 1 and sits(OFF, OFF) and calls.moves[1].routine == where.menu_move and calls.moves[1].menu == menu,
    'The menu goes off screen with the client\'s own mover, with no focus.');
local status = game_buffs.status();
assert(status.held and status.moved == 1 and status.returned == 0, 'The status says the menu is off screen.');
assert(on() == nil and #calls.writes == 2 and #calls.moves == 1 and finds == 7, 'The next Present changes nothing.');

-- With focus, it hands back what the menu's cursor is on, and follows it.
focus(true);
pick = on();
assert(type(pick) == 'table' and pick.effect == 40 and pick.can_cancel == true and #calls.moves == 1, 'The cursor is on Protect.');
put(container + 0x30, le(2, 4));
local again = on();
assert(again == pick and pick.effect == 3 and pick.can_cancel == false, 'The cursor moved to Poison, which can\'t be cancelled, in the same table.');
put(container + 0x30, le(1, 4));
assert(on().effect == 41, 'The cursor moved to Shell.');
-- A list it can't make sense of gives no cursor.
for name, change in pairs({
    -- The client leaves what a longer list held past the end of a shorter one.
    ['a cursor past the list'] = function() put(container + 0x296, le(50, 2)); put(container + 0x30, le(3, 4)); end,
    ['an empty list'] = function() put(container + 0x40, le(0, 4)); end,
    ['a list too long'] = function() put(container + 0x40, le(33, 4)); end,
    ['an effect of 0'] = function() put(container + 0x292, le(0, 2)); end,
    ['an effect past the last one'] = function() put(container + 0x292, le(1024, 2)); end,
}) do
    local kept = snapshot();
    change();
    assert(on() == nil and game_buffs.status().on, name .. ' gives no cursor.');
    mem = kept;
end
assert(on().effect == 41, 'Fixture: the cursor is back on Shell.');
-- Without focus there is no cursor, and the menu stays off screen.
focus(false);
assert(on() == nil and sits(OFF, OFF) and #calls.moves == 1, 'Without focus there is no cursor.');
-- A menu that takes no keys, is closing or is deleted has no cursor either, and it stays off screen all the same.
for name, change in pairs({
    ['a menu that takes no keys'] = function() put(menu + 0x6A, '\0'); end,
    ['a closing menu'] = function() put(menu + 0x10, le(14, 4)); end,
    ['a deleted menu'] = function() put(menu + 0x70, '\1'); end,
}) do
    local kept = snapshot();
    focus(true);
    change();
    assert(on() == nil and sits(OFF, OFF) and game_buffs.status().on, name .. ' has no cursor.');
    mem = kept;
end

-- When the client puts the menu somewhere itself, it goes off screen again, and that place is where it goes back to.
put(menu + 0x52, le(1500, 2) .. le(40, 2));
assert(on() == nil and #calls.moves == 2 and sits(OFF, OFF) and game_buffs.status().moved == 2, 'The client\'s own move is taken off screen again.');

-- Out of effect: the menu goes back and both calls are the client's again, byte for byte.
pick, notice = off();
assert(pick == nil and notice == nil and not game_buffs.status().on and sits(1500, 40) and #calls.moves == 3, 'Out of effect, the menu is back where the client last put it.');
assert(calls_are('the client\'s') and game_buffs.status().returned == 1, 'Out of effect, both calls are back.');
put(menu + 0x52, le(1700, 2) .. le(20, 2));
put(container + 0x30, le(0, 4));
local ok, at = same(before);
assert(ok, ('Everything is as it was: 0x%X differs.'):format(at or 0));
assert(off() == nil and #calls.writes == 4 and #calls.moves == 3, 'Out of effect again, nothing is touched.');

-- Unload does the same.
assert(on() == nil and sits(OFF, OFF));
local clean, why = game_buffs.release();
assert(clean == true and why == nil and sits(1700, 20) and calls_are('the client\'s') and not game_buffs.status().on, 'An unload puts everything back.');

-- A menu the client replaced while Vantage held the old one: the new one goes off screen from its own place, and the
-- old place is never put into it.
fresh();
on();
local other = HEAP + 0x8000;
put(other, get(menu, 0x9C));
put(other + 0x52, le(900, 2) .. le(300, 2));
put(container + 8, le(other, 4));
assert(on() == nil and sits(OFF, OFF, other) and calls.moves[#calls.moves].menu == other and #calls.moves == 2, 'The new menu goes off screen.');
assert(off() == nil and sits(900, 300, other), 'and back to its own place.');
-- A new menu that sits off screen itself has no place Vantage knows, so nothing moves it, at a Present or an unload.
for _, step in ipairs({ 'update', 'release' }) do
    fresh();
    on();
    put(other, get(menu, 0x9C));
    put(container + 8, le(other, 4));
    local count = #calls.moves;
    assert(sits(OFF, OFF, other) and game_buffs.status().held, 'Fixture: the new menu is off screen too.');
    if step == 'update' then assert(on() == nil and not game_buffs.status().held, 'The old menu is forgotten.'); end
    local result = step == 'update' and select(2, off()) or select(2, game_buffs.release());
    assert(result == nil and #calls.moves == count and sits(OFF, OFF, other), 'A new menu off screen is left there by ' .. step .. '.');
end

-- No buff window at all, as at the title screen: nothing to move, and the calls are still skipped and put back.
fresh();
put(SLOT, le(0, 4));
assert(on() == nil and game_buffs.status().on and calls_are('skipped') and #calls.moves == 0, 'With no buff window nothing is moved.');
assert(select(2, off()) == nil and calls_are('the client\'s'), 'And out of effect the calls are back.');

-- A window that isn't the client's buff window is never moved and gives no cursor.
for name, change in pairs({
    ['another name'] = function() put(header + 0x4E, 'loot'); end,
    ['another class'] = function() put(VTABLE + 0x60, le(where.rebuild + 4, 4)); end,
    ['another owner'] = function() put(menu + 0x0C, le(container + 4, 4)); end,
    ['a freed menu'] = function() for index = 0, 0x9B do mem[menu + index] = nil; end end,
}) do
    fresh();
    focus(true);
    change();
    pick, notice = on();
    assert(pick == nil and notice == nil and #calls.moves == 0 and game_buffs.status().on, name .. ' is never moved.');
end

-- The mover is called only when everything it writes can be written. If not, the replacement stops, says so once,
-- and the calls are the client's again. It stays stopped until it has been out of effect once.
for name, change in pairs({
    ['a read-only menu'] = function() heap.from = menu + 0x9C; end,
    ['an object of a kind Vantage doesn\'t know'] = function() put(HEAP + 0x3040, le(7, 2)); end,
    ['a list that loops'] = function() put(HEAP + 0x3200, le(HEAP + 0x3000, 4)); end,
    ['a list that can\'t be read'] = function() put(HEAP + 0x3200, le(HEAP + 0xF000, 4)); end,
    ['an empty list'] = function() put(menu + 0x14, le(0, 4)); end,
    ['a scrollbar that can\'t be written'] = function() put(menu + 0x88, le(CODE + 0x9100, 4)); end,
}) do
    fresh();
    local whole = snapshot();
    change();
    pick, notice = on();
    heap.from = HEAP;
    assert(#calls.moves == 0, name .. ': the mover isn\'t called.');
    assert(pick == nil and notice == CANT_MOVE and game_buffs.problem() == CANT_MOVE, name .. ' is said: ' .. tostring(notice));
    assert(not game_buffs.status().on and calls_are('the client\'s'), name .. ': the calls are put back.');
    local writes = #calls.writes;
    pick, notice = on();
    assert(pick == nil and notice == nil and #calls.writes == writes and not game_buffs.status().on, name .. ' is said once, and nothing is tried again.');
    -- Out of effect once, with the client whole again, it starts again.
    mem = whole;
    off();
    assert(game_buffs.problem() == nil, name .. ': out of effect, the reason is gone.');
    pick, notice = on();
    assert(notice == nil and game_buffs.status().on and sits(OFF, OFF), name .. ': it starts again once it has been out of effect.');
end

-- A move that doesn't land where asked stops it too.
fresh();
calls.stuck = true;
pick, notice = on();
assert(#calls.moves == 1 and pick == nil and notice == CANT_MOVE and not game_buffs.status().on and calls_are('the client\'s'),
    'A move that doesn\'t land stops it: ' .. tostring(notice));
-- A move back that doesn't land leaves the menu off screen, and the game's icons with it, so the game needs a restart.
-- The calls are still put back.
fresh();
on();
calls.stuck = true;
pick, notice = off();
assert(pick == nil and notice == CANT_PUT_BACK and game_buffs.problem() == CANT_PUT_BACK and not game_buffs.status().on and calls_are('the client\'s'),
    'A move back that doesn\'t land: ' .. tostring(notice));
fresh();
on();
calls.stuck = true;
clean, why = game_buffs.release();
assert(clean == false and why == CANT_PUT_BACK and calls_are('the client\'s'), 'An unload that can\'t move it back says so.');

-- A client it doesn't know is left alone: nothing is written, and it says why, once.
local function refused(name, change, wanted)
    fresh();
    change();
    local picked, reason = on();
    assert(picked == nil and type(reason) == 'string' and reason:find(wanted, 1, true), name .. ': ' .. tostring(reason));
    assert(#calls.writes == 0 and #calls.moves == 0 and not game_buffs.status().on, name .. ': nothing is changed.');
    assert(game_buffs.status().problem == reason and game_buffs.problem() == reason, name .. ': the reason is kept.');
    local looked = finds;
    assert(select(2, on()) == nil and finds == looked, name .. ': it is said once, and not looked for again.');
    off();
    local _, same_reason = on();
    assert(same_reason == reason and finds == looked, name .. ': asked for again, it gives the same answer without another search.');
    assert(game_buffs.release() == true and #calls.writes == 0, name .. ': an unload changes nothing either.');
end
-- The mover's own pattern starts on its first bytes, which a hook from another addon or plugin writes a jump over.
-- Its later bytes are then still there, 17 on from its start, and Vantage says what happened. It still changes
-- nothing: the routine isn't the one it knows.
where.menu_move_later = where.menu_move + 17;
local CHANGED = 'Something else in the game, such as another addon or plugin, has changed this game client\'s menu mover, so the game\'s buff icons stay as they are.';
local MISSING = 'This game client\'s menu mover is missing, so the game\'s buff icons stay as they are.';
refused('a mover whose start something else changed', function() missing.menu_move = 'is missing'; end, CHANGED);
assert(finds == 6, 'The later bytes are looked for once the mover isn\'t found, and nothing after it: ' .. finds);
-- A hook's jump over the mover's start, as HeadsUp writes one (a jump and three nops over its first eight bytes):
-- Vantage calls the mover through the hook, at its start, and checks the rest of it.
fresh();
missing.menu_move = 'is missing';
put(where.menu_move, '\233\0\0\0\0\144\144\144');
pick, notice = on();
assert(notice == nil and game_buffs.status().on and sits(OFF, OFF) and calls.moves[#calls.moves].routine == where.menu_move,
    'A hooked mover is called through its hook: ' .. tostring(notice));
off();
fresh();
missing.menu_move = 'is missing';
put(where.menu_move, '\233\0\0\0\0\144\144\144');
put(where.menu_move + 0xE0, '\204');
local _, hooked_other = on();
assert(hooked_other == 'This game client\'s menu mover is not the code Vantage knows, so the game\'s buff icons stay as they are.'
    and #calls.writes == 0, 'A hooked mover whose later bytes differ is still refused: ' .. tostring(hooked_other));
off();
refused('a routine that is missing', function() missing.menu_move, missing.menu_move_later = 'is missing', 'is missing'; end, MISSING);
refused('a mover missing whose later bytes are there twice',
    function() missing.menu_move, missing.menu_move_later = 'is missing', 'matches more than once'; end, MISSING);
refused('a mover found twice', function() missing.menu_move = 'matches more than once'; end,
    'This game client\'s menu mover matches more than once, so the game\'s buff icons stay as they are.');
assert(finds == 5, 'A mover found twice is not looked for by its later bytes: ' .. finds);
refused('another routine that is missing', function() missing.timer_draw = 'is missing'; end,
    'This game client\'s timer drawing is missing, so the game\'s buff icons stay as they are.');
assert(finds == 4, 'Only the mover has later bytes to look for: ' .. finds);
-- A search that finds nothing and gives no reason counts as a routine that is missing.
local kept = where.rebuild;
refused('a routine a search gives no reason for', function() where.rebuild = nil; end,
    'This game client\'s buff list rebuild is missing, so the game\'s buff icons stay as they are.');
where.rebuild, kept = kept, where.menu_move;
refused('a mover a search gives no reason for', function() where.menu_move = nil; end, CHANGED);
where.menu_move = kept;
refused('a routine found twice', function() missing.icon_paint = 'matches more than once'; end,
    'This game client\'s buff icon painting matches more than once, so the game\'s buff icons stay as they are.');
refused('a routine with other bytes', function() put(where.menu_move + 0xE0, '\204'); end,
    'This game client\'s menu mover is not the code Vantage knows, so the game\'s buff icons stay as they are.');
refused('an icon draw that clears another count', function() put(where.icon_draw + 0x19C, '\24'); end,
    'This game client\'s icon drawing is not the code Vantage knows');
refused('a routine that can\'t be read', function() for index = 0, 15 do mem[where.timer_draw + 0x100 + index] = nil; end end,
    'This game client\'s timer drawing is not the code Vantage knows');
refused('a paint that names another slot', function() put(where.icon_paint + 0xC7, le(SLOT + 4, 4)); end,
    'This game client\'s buff window was not found where Vantage looks');
refused('a slot that can\'t be read', function() for index = 0, 3 do mem[SLOT + index] = nil; end end,
    'This game client\'s buff window was not found where Vantage looks');
refused('a manager that can\'t be read', function() for index = 0, 0x5F do mem[MANAGER + index] = nil; end end,
    'This game client\'s buff window was not found where Vantage looks');
refused('a call something else changed', function() put(ICON, call(ICON, where.icon_draw + 16)); end,
    'Something else already changed the game\'s buff drawing, so Vantage leaves it alone.');
refused('a call that is no call', function() put(TIMER, '\233' .. le(0, 4)); end,
    'Something else already changed the game\'s buff drawing, so Vantage leaves it alone.');

-- A client that can't be reached at all.
game_buffs._set_platform(nil);
pick, notice = on();
assert(pick == nil and notice == CANT_REACH and game_buffs.release() == true, 'No platform: ' .. tostring(notice));

-- A write that fails on the second call puts the first back.
fresh();
calls.fail_write = 2;
pick, notice = on();
assert(pick == nil and notice == 'Vantage could not change the game\'s buff drawing, so the game\'s buff icons stay as they are.'
    and not game_buffs.status().on and #calls.moves == 0, 'A write that fails: ' .. tostring(notice));
assert(calls_are('the client\'s'), 'The first call is put back.');

-- Skipped calls left from an unload that couldn't put them back are taken as they are, and out of effect they are
-- calls again.
fresh();
put(ICON, game_buffs._ICON_SKIP);
put(TIMER, game_buffs._TIMER_SKIP);
assert(select(2, on()) == nil and game_buffs.status().on and #calls.writes == 0, 'Calls already skipped are left as they are.');
assert(select(2, off()) == nil and calls_are('the client\'s'), 'Out of effect, the client\'s calls are written back.');

-- Out of effect when a call holds something else: it is left alone, and the game needs a restart.
fresh();
on();
put(ICON, '\233' .. le(0, 4));
pick, notice = off();
assert(notice == CANT_PUT_BACK and not game_buffs.status().on, 'A call that can\'t be put back: ' .. tostring(notice));
assert(get(ICON, 5) == '\233' .. le(0, 4) and get(TIMER, 5) == call(TIMER, where.timer_draw), 'Only Vantage\'s own bytes are written over.');
return 'Replace the game\'s buff icons, the game side';
