local assdraw = require 'mp.assdraw'
local msg = require 'mp.msg'
local opt = require 'mp.options'
local utils = require 'mp.utils'

-- Disable built-in player UI
mp.set_property("osc", "no")

--
-- Parameters
--
-- default user option values
-- no need to touch, change them in osc.conf
local user_opts = {
    showwindowed = true,        -- show OSC when windowed?
    showfullscreen = true,      -- show OSC when fullscreen?
    scalewindowed = 1.0,        -- scaling of the controller when windowed
    scalefullscreen = 1.0,      -- scaling of the controller when fullscreen
    scaleforcedwindow = 1.0,    -- scaling when rendered on a forced window
    vidscale = false,           -- scale the controller with the video?
    valign = 1,                 -- vertical alignment, -1 (top) to 1 (bottom)
    halign = 0,                 -- horizontal alignment, -1 (left) to 1 (right)
    barmargin = 0,              -- vertical margin of top/bottombar
    boxalpha = 110,             -- alpha of the background box
	buttonalpha = 80,			-- alpha of buttons
                                -- 0 (opaque) to 255 (fully transparent)
    hidetimeout = 100,          -- duration in ms until the OSC hides if no
                                -- mouse movement. enforced non-negative for the
                                -- user, but internally negative is "always-on".
    fadeduration = 500,         -- duration of fade out in ms, 0 = no fade
    deadzonesize = 1,           -- size of deadzone
    minmousemove = 0,           -- minimum amount of pixels the mouse has to
                                -- move between ticks to make the OSC show up
    iamaprogrammer = false,     -- use native mpv values and disable OSC
                                -- internal track list management (and some
                                -- functions that depend on it)
	font = "mpv-osd-symbols",	-- default osc font
    layout = "default",			-- default only!!
    seekbarstyle = "knob",      -- bar, diamond or knob
    seekbarhandlesize = 3.5,	-- size ratio of the diamond and knob handle
    seekrangestyle = "bar",		-- bar, line, slider, inverted or none
    seekrangeseparate = true,   -- wether the seekranges overlay on the bar-style seekbar
    seekrangealpha = 180,       -- transparency of seekranges
    seekbarkeyframes = true,    -- use keyframes when dragging the seekbar
    title = " ${filename/no-ext}",   -- string compatible with property-expansion
                                -- to be shown as OSC title
    tooltipborder = 1,          -- border of tooltip in bottom/topbar
    timetotal = true,           -- display total time instead of remaining time?
    timems = false,             -- display timecodes with milliseconds?
    visibility = "auto",        -- only used at init to set visibility_mode(...)
    boxmaxchars = 128,          -- title crop threshold for box layout
	wcmaxchars = 96,            -- window control title crop threshold
    boxvideo = false,           -- apply osc_param.video_margins to video
    windowcontrols = "auto",    -- whether to show window controls
    windowcontrols_alignment = "right", -- which side to show window controls on
    logotext = "Drop files or URLs to play here",
								-- this text appears when mpv starts
	showchaptertooltip = true,
}

-- read options from config and command-line
opt.read_options(user_opts, "osc", function(list) update_options(list) end)

local thumbfast = {
    width = 0,
    height = 0,
    disabled = false
}
local thumbfast_available = false

local osc_param = { -- calculated by osc_init()
    playresy = 0,                           -- canvas size Y
    playresx = 0,                           -- canvas size X
    display_aspect = 1,
    unscaled_y = 0,
    areas = {},
    video_margins = {
        l = 0, r = 0, t = 0, b = 0,         -- left/right/top/bottom
    },
}

local splash = {
	-- Colors
	darkBgColor = "211913",
	BgColor = "2E2319",
	
	brightRed = "5529DF",
	
	brightButtonColor = "F1F1F1",
	dimButtonColor = "574932",
	
	-- Sizes
	buttonTooltipSize = 20,
}

local osc_styles = {
    s32Button = "{\\blur0\\bord0\\1c&HCAC1B8\\3c&HFFFFFF\\fs30\\fnMaterial Icons Round}",
	s24Button = "{\\blur0\\bord0\\1c&H" .. splash.dimButtonColor .. "\\3c&HFFFFFF\\fs24\\fnMaterial Icons Round}",
    -- s16Button = "{\\blur0\\bord0\\1c&H" .. splash.dimButtonColor .. "\\3c&HFFFFFF\\fs16\\fn" .. user_opts.font .. "}",
	s12Button = "{\\blur0\\bord0\\1c&HEDF7FF\\3c&HFFFFFF\\fs16\\fnSegoe UI Light}",
    cyButton = "{\\blur0\\bord0\\1c&HF4EFED\\3c&HFFFFFF\\fs20\\fnmpv-osd-symbols}",
    cyDigit = "{\\fn" .. user_opts.font .. "}",
    divA = "{\\blur0\\bord0\\1c&H161211\\3c&HFFFFFF\\fs16\\fnmpv-osd-symbols}",
    divB = "{\\blur0\\bord0\\1c&H8E807D\\3c&HFFFFFF\\fs16\\fnmpv-osd-symbols}",
    bgBox = "{\\rDefault\\blur0\\bord0\\1c&H" .. splash.BgColor .. "\\3c&HFFFFFF}",
	bgBox2 = "{\\rDefault\\blur0\\bord0\\1c&H" .. splash.darkBgColor .. "\\3c&HFFFFFF}", 
    fgSeekbar = "{\\blur0\\bord0\\1c&H" .. splash.brightRed .. "\\3c&HFFFFFF\\fs13}",
    tpSeekbar = "{\\blur2\\bord".. user_opts.tooltipborder .."\\1c&HFFFFFF\\3c&H000000\\fs24}",
    bgSeekbar = "{\\blur0\\bord0\\c&H000000\\3c&H000000\\fs13\\q2}",
	
	splashlogo = "{\\rDefault\\an7\\1c&H591BFF\\1a&H00&\\bord0\\shad0\\fs36\\fscx130\\fnMaterial Icons Round}",
	splashtext = "{\\rDefault\\an7\\1c&HFEFEFE\\1a&H00&\\bord0\\shad0\\fs22\\fsp0.5\\fnYaro Rg}",

    wcButtons = "{\\1c&H787878\\fs24\\fnmpv-osd-symbols}",
    wcTitle = "{\\1c&HEDF7FF\\3c&HFFFFFF\\fs14\\fnSegoe UI Light\\q2}",
	wcExt = "{\\1c&HEDF7FF\\3c&HFFFFFF\\fs15\\fnSegoe UI Light\\q2}",
    wcBar = "{\\1c&H31251B}",
	
    elementDown = "{\\1c&H999999}",
	
	buttonHoveredColor = "F0F0F0",
    buttonHoveredRectColor = "000000",
    buttonHoveredRectAlpha = 255,
}

-- https://github.com/libass/libass/wiki/ASSv5-Override-Tags#color-and-alpha---c-o
function genColorStyle(color)
    return "{\\c&H"..color.."&}" -- Not sure why &H...& is used in santa_hat_lines
    -- return "{\\c("..color..")}" -- Works
    -- return "{\\c(#"..color..")}" -- Only works for paths, and breaks other stuff.
end

	osc_styles.buttonHovered = genColorStyle(osc_styles.buttonHoveredColor)

-- internal states, do not touch
local state = {
    showtime,                               -- time of last invocation (last mouse move)
    osc_visible = false,
    anistart,                               -- time when the animation started
    anitype,                                -- current type of animation
    animation,                              -- current animation alpha
    mouse_down_counter = 0,                 -- used for softrepeat
    active_element = nil,                   -- nil = none, 0 = background, 1+ = see elements[]
    active_event_source = nil,              -- the "button" that issued the current event
    rightTC_trem = not user_opts.timetotal, -- if the right timecode should display total or remaining time
    tc_ms = user_opts.timems,               -- Should the timecodes display their time with milliseconds
    mp_screen_sizeX, mp_screen_sizeY,       -- last screen-resolution, to detect resolution changes to issue reINITs
    initREQ = false,                        -- is a re-init request pending?
    last_mouseX, last_mouseY,               -- last mouse position, to detect significant mouse movement
    mouse_in_window = false,
    message_text,
    message_hide_timer,
    fullscreen = false,
    tick_timer = nil,
    tick_last_time = 0,                     -- when the last tick() was run
    hide_timer = nil,
    cache_state = nil,
    idle = false,
    enabled = true,
    input_enabled = true,
    showhide_enabled = false,
    dmx_cache = 0,
    using_video_margins = false,
    border = true,
    maximized = false,
    osd = mp.create_osd_overlay("ass-events"),
	chapter_list = {},
}

local window_control_box_width = 80
local tick_delay = 0.03

local is_december = os.date("*t").month == 12

--
-- Helperfunctions
--

function set_osd(res_x, res_y, text)
    if state.osd.res_x == res_x and
       state.osd.res_y == res_y and
       state.osd.data == text then
        return
    end
    state.osd.res_x = res_x
    state.osd.res_y = res_y
    state.osd.data = text
    state.osd.z = 1000
    state.osd:update()
end

local margins_opts = {
    {"l", "video-margin-ratio-left"},
    {"r", "video-margin-ratio-right"},
    {"t", "video-margin-ratio-top"},
    {"b", "video-margin-ratio-bottom"},
}

-- scale factor for translating between real and virtual ASS coordinates
function get_virt_scale_factor()
    local w, h = mp.get_osd_size()
    if w <= 0 or h <= 0 then
        return 0, 0
    end
    return osc_param.playresx / w, osc_param.playresy / h
end

-- return mouse position in virtual ASS coordinates (playresx/y)
function get_virt_mouse_pos()
    if state.mouse_in_window then
        local sx, sy = get_virt_scale_factor()
        local x, y = mp.get_mouse_pos()
        return x * sx, y * sy
    else
        return -1, -1
    end
end

function set_virt_mouse_area(x0, y0, x1, y1, name)
    local sx, sy = get_virt_scale_factor()
    mp.set_mouse_area(x0 / sx, y0 / sy, x1 / sx, y1 / sy, name)
end

function scale_value(x0, x1, y0, y1, val)
    local m = (y1 - y0) / (x1 - x0)
    local b = y0 - (m * x0)
    return (m * val) + b
end

-- returns hitbox spanning coordinates (top left, bottom right corner)
-- according to alignment
function get_hitbox_coords(x, y, an, w, h)

    local alignments = {
      [1] = function () return x, y-h, x+w, y end,
      [2] = function () return x-(w/2), y-h, x+(w/2), y end,
      [3] = function () return x-w, y-h, x, y end,

      [4] = function () return x, y-(h/2), x+w, y+(h/2) end,
      [5] = function () return x-(w/2), y-(h/2), x+(w/2), y+(h/2) end,
      [6] = function () return x-w, y-(h/2), x, y+(h/2) end,

      [7] = function () return x, y, x+w, y+h end,
      [8] = function () return x-(w/2), y, x+(w/2), y+h end,
      [9] = function () return x-w, y, x, y+h end,
    }

    return alignments[an]()
end

function get_hitbox_coords_geo(geometry)
    return get_hitbox_coords(geometry.x, geometry.y, geometry.an,
        geometry.w, geometry.h)
end

function get_element_hitbox(element)
    return element.hitbox.x1, element.hitbox.y1,
        element.hitbox.x2, element.hitbox.y2
end

function mouse_hit(element)
    return mouse_hit_coords(get_element_hitbox(element))
end

function mouse_hit_coords(bX1, bY1, bX2, bY2)
    local mX, mY = get_virt_mouse_pos()
    return (mX >= bX1 and mX <= bX2 and mY >= bY1 and mY <= bY2)
end

function limit_range(min, max, val)
    if val > max then
        val = max
    elseif val < min then
        val = min
    end
    return val
end

-- translate value into element coordinates
function get_slider_ele_pos_for(element, val)

    local ele_pos = scale_value(
        element.slider.min.value, element.slider.max.value,
        element.slider.min.ele_pos, element.slider.max.ele_pos,
        val)

    return limit_range(
        element.slider.min.ele_pos, element.slider.max.ele_pos,
        ele_pos)
end

-- translates global (mouse) coordinates to value
function get_slider_value_at(element, glob_pos)

    local val = scale_value(
        element.slider.min.glob_pos, element.slider.max.glob_pos,
        element.slider.min.value, element.slider.max.value,
        glob_pos)

    return limit_range(
        element.slider.min.value, element.slider.max.value,
        val)
end

-- get value at current mouse position
function get_slider_value(element)
    return get_slider_value_at(element, get_virt_mouse_pos())
end

function countone(val)
    if not (user_opts.iamaprogrammer) then
        val = val + 1
    end
    return val
end

-- align:  -1 .. +1
-- frame:  size of the containing area
-- obj:    size of the object that should be positioned inside the area
-- margin: min. distance from object to frame (as long as -1 <= align <= +1)
function get_align(align, frame, obj, margin)
    return (frame / 2) + (((frame / 2) - margin - (obj / 2)) * align)
end

-- multiplies two alpha values, formular can probably be improved
function mult_alpha(alphaA, alphaB)
    return 255 - (((1-(alphaA/255)) * (1-(alphaB/255))) * 255)
end

function add_area(name, x1, y1, x2, y2)
    -- create area if needed
    if (osc_param.areas[name] == nil) then
        osc_param.areas[name] = {}
    end
    table.insert(osc_param.areas[name], {x1=x1, y1=y1, x2=x2, y2=y2})
end

function ass_append_alpha(ass, alpha, modifier)
    local ar = {}

    for ai, av in pairs(alpha) do
        av = mult_alpha(av, modifier)
        if state.animation then
            av = mult_alpha(av, state.animation)
        end
        ar[ai] = av
    end

    ass:append(string.format("{\\1a&H%X&\\2a&H%X&\\3a&H%X&\\4a&H%X&}",
               ar[1], ar[2], ar[3], ar[4]))
end

function ass_draw_rr_h_cw(ass, x0, y0, x1, y1, r1, hexagon, r2)
    if hexagon then
        ass:hexagon_cw(x0, y0, x1, y1, r1, r2)
    else
        ass:round_rect_cw(x0, y0, x1, y1, r1, r2)
    end
end

function ass_draw_rr_h_ccw(ass, x0, y0, x1, y1, r1, hexagon, r2)
    if hexagon then
        ass:hexagon_ccw(x0, y0, x1, y1, r1, r2)
    else
        ass:round_rect_ccw(x0, y0, x1, y1, r1, r2)
    end
end


--
-- Tracklist Management
--

local nicetypes = {video = "Video", audio = "Audio", sub = "Subtitle"}

-- updates the OSC internal playlists, should be run each time the track-layout changes
function update_tracklist()
    local tracktable = mp.get_property_native("track-list", {})

    -- by osc_id
    tracks_osc = {}
    tracks_osc.video, tracks_osc.audio, tracks_osc.sub = {}, {}, {}
    -- by mpv_id
    tracks_mpv = {}
    tracks_mpv.video, tracks_mpv.audio, tracks_mpv.sub = {}, {}, {}
    for n = 1, #tracktable do
        if not (tracktable[n].type == "unknown") then
            local type = tracktable[n].type
            local mpv_id = tonumber(tracktable[n].id)

            -- by osc_id
            table.insert(tracks_osc[type], tracktable[n])

            -- by mpv_id
            tracks_mpv[type][mpv_id] = tracktable[n]
            tracks_mpv[type][mpv_id].osc_id = #tracks_osc[type]
        end
    end
end

-- return a nice list of tracks of the given type (video, audio, sub)
function get_tracklist(type)
    local msg = "Available " .. nicetypes[type] .. " Tracks: "
    if #tracks_osc[type] == 0 then
        msg = msg .. "none"
    else
        for n = 1, #tracks_osc[type] do
            local track = tracks_osc[type][n]
            local lang, title, selected = "unknown", "", "○"
            if not(track.lang == nil) then lang = track.lang end
            if not(track.title == nil) then title = track.title end
            if (track.id == tonumber(mp.get_property(type))) then
                selected = "●"
            end
            msg = msg.."\n"..selected.." "..n..": ["..lang.."] "..title
        end
    end
    return msg
end

-- relatively change the track of given <type> by <next> tracks
    --(+1 -> next, -1 -> previous)
function set_track(type, next)
    local current_track_mpv, current_track_osc
    if (mp.get_property(type) == "no") then
        current_track_osc = 0
    else
        current_track_mpv = tonumber(mp.get_property(type))
        current_track_osc = tracks_mpv[type][current_track_mpv].osc_id
    end
    local new_track_osc = (current_track_osc + next) % (#tracks_osc[type] + 1)
    local new_track_mpv
    if new_track_osc == 0 then
        new_track_mpv = "no"
    else
        new_track_mpv = tracks_osc[type][new_track_osc].id
    end

    mp.commandv("set", type, new_track_mpv)

        if (new_track_osc == 0) then
        show_message(nicetypes[type] .. " Track: none")
    else
        show_message(nicetypes[type]  .. " Track: "
            .. new_track_osc .. "/" .. #tracks_osc[type]
            .. " [".. (tracks_osc[type][new_track_osc].lang or "unknown") .."] "
            .. (tracks_osc[type][new_track_osc].title or ""))
    end
end

-- get the currently selected track of <type>, OSC-style counted
function get_track(type)
    local track = mp.get_property(type)
    if track ~= "no" and track ~= nil then
        local tr = tracks_mpv[type][tonumber(track)]
        if tr then
            return tr.osc_id
        end
    end
    return 0
end

-- WindowControl helpers
function window_controls_enabled()
    val = user_opts.windowcontrols
    if val == "auto" then
        return not state.border
    else
        return val ~= "no"
    end
end

function window_controls_alignment()
    return user_opts.windowcontrols_alignment
end

--
-- Element Management
--

local elements = {}

function prepare_elements()

    -- remove elements without layout or invisble
    local elements2 = {}
    for n, element in pairs(elements) do
        if not (element.layout == nil) and (element.visible) then
            table.insert(elements2, element)
        end
    end
    elements = elements2

    function elem_compare (a, b)
        return a.layout.layer < b.layout.layer
    end

    table.sort(elements, elem_compare)


    for _,element in pairs(elements) do

        local elem_geo = element.layout.geometry

        -- Calculate the hitbox
        local bX1, bY1, bX2, bY2 = get_hitbox_coords_geo(elem_geo)
        element.hitbox = {x1 = bX1, y1 = bY1, x2 = bX2, y2 = bY2}

        local style_ass = assdraw.ass_new()

        -- prepare static elements
        style_ass:append("{}") -- hack to troll new_event into inserting a \n
        style_ass:new_event()
        style_ass:pos(elem_geo.x, elem_geo.y)
        style_ass:an(elem_geo.an)
        style_ass:append(element.layout.style)

        element.style_ass = style_ass

        local static_ass = assdraw.ass_new()


        if (element.type == "box") then
            --draw box
            static_ass:draw_start()
            ass_draw_rr_h_cw(static_ass, 0, 0, elem_geo.w, elem_geo.h,
                             element.layout.box.radius, element.layout.box.hexagon)
            static_ass:draw_stop()

        elseif (element.type == "slider") then
            --draw static slider parts
            local r1 = 0
            local r2 = 0
            local slider_lo = element.layout.slider
            -- offset between element outline and drag-area
            local foV = slider_lo.border + slider_lo.gap

            -- calculate positions of min and max points
            if (slider_lo.stype ~= "bar") then
                r1 = elem_geo.h / 2
                element.slider.min.ele_pos = elem_geo.h / 2
                element.slider.max.ele_pos = elem_geo.w - (elem_geo.h / 2)
                if (slider_lo.stype == "diamond") then
                    r2 = (elem_geo.h - 2 * slider_lo.border) / 2
                elseif (slider_lo.stype == "knob") then
                    r2 = r1
                end
            else
                element.slider.min.ele_pos =
                    slider_lo.border + slider_lo.gap
                element.slider.max.ele_pos =
                    elem_geo.w - (slider_lo.border + slider_lo.gap)
            end

            element.slider.min.glob_pos =
                element.hitbox.x1 + element.slider.min.ele_pos
            element.slider.max.glob_pos =
                element.hitbox.x1 + element.slider.max.ele_pos

            -- -- --

            static_ass:draw_start()

            -- the box
            ass_draw_rr_h_cw(static_ass, 0, 0, elem_geo.w, elem_geo.h, r1, slider_lo.stype == "diamond")

            -- the "hole"
            ass_draw_rr_h_ccw(static_ass, slider_lo.border, slider_lo.border,
                              elem_geo.w - slider_lo.border, elem_geo.h - slider_lo.border,
                              r2, slider_lo.stype == "diamond")

            -- marker nibbles
            if not (element.slider.markerF == nil) and (slider_lo.gap > 0) then
                local markers = element.slider.markerF()
                for _,marker in pairs(markers) do
                    if (marker > element.slider.min.value) and
                        (marker < element.slider.max.value) then

                        local s = get_slider_ele_pos_for(element, marker)

                        if (slider_lo.gap > 1) then -- draw triangles

                            local a = slider_lo.gap / 0.5 --0.866

                            --top
                            if (slider_lo.nibbles_top) then
                                static_ass:move_to(s - (a/2), slider_lo.border)
                                static_ass:line_to(s + (a/2), slider_lo.border)
                                static_ass:line_to(s, foV)
                            end

                            --bottom
                            if (slider_lo.nibbles_bottom) then
                                static_ass:move_to(s - (a/2),
                                    elem_geo.h - slider_lo.border)
                                static_ass:line_to(s,
                                    elem_geo.h - foV)
                                static_ass:line_to(s + (a/2),
                                    elem_geo.h - slider_lo.border)
                            end

                        else -- draw 2x1px nibbles

                            --top
                            if (slider_lo.nibbles_top) then
                                static_ass:rect_cw(s - 1, slider_lo.border,
                                    s + 1, slider_lo.border + slider_lo.gap);
                            end

                            --bottom
                            if (slider_lo.nibbles_bottom) then
                                static_ass:rect_cw(s - 1,
                                    elem_geo.h -slider_lo.border -slider_lo.gap,
                                    s + 1, elem_geo.h - slider_lo.border);
                            end
                        end
                    end
                end
            end
        end

        element.static_ass = static_ass


        -- if the element is supposed to be disabled,
        -- style it accordingly and kill the eventresponders
        if not (element.enabled) then
            element.layout.alpha[1] = 136
            element.eventresponder = nil
        end
    end
end


--
-- Element Rendering
--

-- returns nil or a chapter element from the native property chapter-list
-- chapter titles that are just auto-generated timestamps (e.g. "00:06:35.562")
-- are meaningless to display, so treat them as "no title"
function is_timestamp_title(title)
    return title ~= nil and title:match("^%d+:%d+:%d+[%.,]?%d*$") ~= nil
end

function get_chapter(possec)
    local cl = state.chapter_list  -- sorted, get latest before possec, if any

    for n=#cl,1,-1 do
        if possec >= cl[n].time then
            return cl[n]
        end
    end
end

function render_elements(master_ass)

    -- when the slider is dragged or hovered and we have a target chapter name
    -- then we use it instead of the normal title. we calculate it before the
    -- render iterations because the title may be rendered before the slider.
    state.forced_title = nil
    local se, ae = state.slider_element, elements[state.active_element]
    if user_opts.chapter_fmt ~= "no" and se and (ae == se or (not ae and mouse_hit(se))) then
        local dur = mp.get_property_number("duration", 0)
        if dur > 0 then
            local possec = get_slider_value(se) * dur / 100 -- of mouse pos
            local ch = get_chapter(possec)
            if ch and ch.title and ch.title ~= "" and not is_timestamp_title(ch.title) then
                state.forced_title = string.format(user_opts.chapter_fmt, ch.title)
            end
        end
    end

    for n=1, #elements do
        local element = elements[n]

        local style_ass = assdraw.ass_new()
        style_ass:merge(element.style_ass)
        ass_append_alpha(style_ass, element.layout.alpha, 0)

        if element.eventresponder and (state.active_element == n) then

            -- run render event functions
            if not (element.eventresponder.render == nil) then
                element.eventresponder.render(element)
            end

            if mouse_hit(element) then
                -- mouse down styling
                if (element.styledown) then
                    style_ass:append(osc_styles.elementDown)
                end

                if (element.softrepeat) and (state.mouse_down_counter >= 15
                    and state.mouse_down_counter % 5 == 0) then

                    element.eventresponder[state.active_event_source.."_down"](element)
                end
                state.mouse_down_counter = state.mouse_down_counter + 1
            end

        end

        local elem_ass = assdraw.ass_new()

        elem_ass:merge(style_ass)

        if not (element.type == "button") then
            elem_ass:merge(element.static_ass)
        end

        if (element.type == "slider") then

            local slider_lo = element.layout.slider
            local elem_geo = element.layout.geometry
            local s_min = element.slider.min.value
            local s_max = element.slider.max.value

            -- draw pos marker
            local foH, xp
            local pos = element.slider.posF()
            local foV = slider_lo.border + slider_lo.gap
            local innerH = (elem_geo.h - slider_lo.seekbar_offset) - (2 * foV)
            local seekRanges = element.slider.seekRangesF()
            local seekRangeLineHeight = innerH / 5

            if slider_lo.stype ~= "bar" then
                foH = elem_geo.h * user_opts.seekbarhandlesize / 2 - (slider_lo.border + slider_lo.gap) * user_opts.seekbarhandlesize
            else
                foH = slider_lo.border + slider_lo.gap
            end

            if pos then
                xp = get_slider_ele_pos_for(element, pos)

                if slider_lo.stype ~= "bar" then
                    local r = innerH / 2							-- Bar radius
                    local rh = r * user_opts.seekbarhandlesize		-- Handle radius
                    s_min = s_min + slider_lo.border + slider_lo.gap
                    s_max = s_max - slider_lo.border - slider_lo.gap
                    ass_draw_rr_h_cw(elem_ass, xp - rh, foH - rh - (1.7 * slider_lo.seekbar_offset),
                                     xp + rh, foH + rh - (1.7 * slider_lo.seekbar_offset),
                                     rh, slider_lo.stype == "diamond")
					ass_draw_rr_h_cw(elem_ass, s_min, foH - r - (1.7 * slider_lo.seekbar_offset),
                                     xp, foH + r - (1.7 * slider_lo.seekbar_offset),
                                     r, slider_lo.stype == "diamond")
                else
                    local h = 0
                    if seekRanges and user_opts.seekrangeseparate and slider_lo.rtype ~= "inverted" then
                        h = seekRangeLineHeight
                    end
                    elem_ass:rect_cw(foH, foV, xp, elem_geo.h - foV - h)

                    if seekRanges and not user_opts.seekrangeseparate and slider_lo.rtype ~= "inverted" then
                        -- Punch holes for the seekRanges to be drawn later
                        for _,range in pairs(seekRanges) do
                            if range["start"] < pos then
                                local pstart = get_slider_ele_pos_for(element, range["start"])
                                local pend = xp

                                if pos > range["end"] then
                                    pend = get_slider_ele_pos_for(element, range["end"])
                                end
                                elem_ass:rect_ccw(pstart, elem_geo.h - foV - seekRangeLineHeight, pend, elem_geo.h - foV)
                            end
                        end
                    end
                end

                if slider_lo.rtype == "slider" then
                    ass_draw_rr_h_cw(elem_ass, foH - innerH / 6, foH - innerH / 6,
                                     xp, foH + innerH / 6,
                                     innerH / 6, slider_lo.stype == "diamond", 0)
                    ass_draw_rr_h_cw(elem_ass, xp, foH - innerH / 15,
                                     elem_geo.w - foH + innerH / 15, foH + innerH / 15,
                                     0, slider_lo.stype == "diamond", innerH / 15)
                    for _,range in pairs(seekRanges or {}) do
                        local pstart = get_slider_ele_pos_for(element, range["start"])
                        local pend = get_slider_ele_pos_for(element, range["end"])
                        ass_draw_rr_h_ccw(elem_ass, pstart, foH - innerH / 21,
                                          pend, foH + innerH / 21,
                                          innerH / 21, slider_lo.stype == "diamond")
                    end
                end
            end

            if seekRanges then
                if slider_lo.rtype ~= "inverted" then
                    elem_ass:draw_stop()
                    elem_ass:merge(element.style_ass)
                    ass_append_alpha(elem_ass, element.layout.alpha, user_opts.seekrangealpha)
                    elem_ass:merge(element.static_ass)
                end

                for _,range in pairs(seekRanges) do
                    local pstart = get_slider_ele_pos_for(element, range["start"])
                    local pend = get_slider_ele_pos_for(element, range["end"])

                    if slider_lo.rtype == "slider" then
                        ass_draw_rr_h_cw(elem_ass, pstart, foH - innerH / 21,
                                         pend, foH + innerH / 21,
                                         innerH / 21, slider_lo.stype == "diamond")
                    elseif slider_lo.rtype == "line" then
                        if slider_lo.stype == "bar" then
                            elem_ass:rect_cw(pstart, elem_geo.h - foV - seekRangeLineHeight, pend, elem_geo.h - foV)
                        else
                            ass_draw_rr_h_cw(elem_ass, pstart - innerH / 8, foH - innerH / 8,
                                             pend + innerH / 8, foH + innerH / 8,
                                             innerH / 8, slider_lo.stype == "diamond")
                        end
                    elseif slider_lo.rtype == "bar" then
                        if slider_lo.stype ~= "bar" then
                            ass_draw_rr_h_cw(elem_ass, pstart - innerH / 2, foV,
                                             pend + innerH / 2, foV + innerH,
                                             innerH / 2, slider_lo.stype == "diamond")
                        elseif range["end"] >= (pos or 0) then
                            elem_ass:rect_cw(pstart, foV, pend, elem_geo.h - foV)
                        else
                            elem_ass:rect_cw(pstart, elem_geo.h - foV - seekRangeLineHeight, pend, elem_geo.h - foV)
                        end
                    elseif slider_lo.rtype == "inverted" then
                        if slider_lo.stype ~= "bar" then
                            ass_draw_rr_h_ccw(elem_ass, pstart, (elem_geo.h*user_opts.seekbarhandlesize / 2) - 1, pend,
                                              (elem_geo.h*user_opts.seekbarhandlesize / 2) + 1,
                                              1, slider_lo.stype == "diamond")
                        else
                            elem_ass:rect_ccw(pstart, (elem_geo.h / 2) - 1, pend, (elem_geo.h / 2) + 1)
                        end
                    end
                end
            end

            elem_ass:draw_stop()

            -- add tooltip
            if not (element.slider.tooltipF == nil) then

                if mouse_hit(element) then
                    local sliderpos = get_slider_value(element)
                    local tooltiplabel = element.slider.tooltipF(sliderpos)

                    local an = slider_lo.tooltip_an

                    local ty

                    if (an == 2) then
                        ty = element.hitbox.y1 - slider_lo.border 
                    else
                        ty = element.hitbox.y1 + elem_geo.h/2
                    end

                    local tx = get_virt_mouse_pos()
                    if (slider_lo.adjust_tooltip) then
                        if (an == 2) then
                            if (sliderpos < (s_min + 3)) then
                                an = an - 1
                            elseif (sliderpos > (s_max - 3)) then
                                an = an + 1
                            end
                        elseif (sliderpos > (s_max-s_min)/2) then
                            an = an + 1
                            tx = tx - 5
                        else
                            an = an - 1
                            tx = tx + 10
                        end
                    end
					
                    -- tooltip label
					local mouseX, mouseY = get_virt_mouse_pos()
                    elem_ass:new_event()
                    elem_ass:pos(tx, mouseY+5)
                    elem_ass:an(an)
                    elem_ass:append(slider_lo.tooltip_style)
                    ass_append_alpha(elem_ass, slider_lo.alpha, 0)
                    elem_ass:append(tooltiplabel)
					
                    
                    -- thumbnail
                    if not thumbfast.disabled and thumbfast.width ~= 0 and thumbfast.height ~= 0 then
                        local osd_w = mp.get_property_number("osd-dimensions/w")
                        if osd_w then
                            local r_w, r_h = get_virt_scale_factor()

                            local thumbPad = 3
                            local thumbMarginX = 18 / r_w
                            local thumbMarginY = 35
                            local tooltipBgColor = splash.darkBgColor
                            local tooltipBgAlpha = 125
                            local thumbX = math.min(osd_w - thumbfast.width - thumbMarginX, math.max(thumbMarginX, tx / r_w - thumbfast.width / 2))
                            local thumbY = ((ty - thumbMarginY) / r_h - thumbfast.height)
							
							local mousethumbY = ((mouseY - thumbMarginY) / r_h - thumbfast.height)
                            
							elem_ass:new_event()
                            elem_ass:pos(thumbX * r_w, mousethumbY * r_h)
                            elem_ass:append(("{\\bord0\\1c&H%s&\\1a&H%X&}"):format(tooltipBgColor, tooltipBgAlpha))
                            elem_ass:draw_start()
                            elem_ass:rect_cw(-thumbPad * r_h, -thumbPad * r_h, (thumbfast.width + thumbPad) * r_w, (thumbfast.height + thumbPad) * r_h)
                            

                            mp.commandv("script-message-to", "thumbfast", "thumb",
                                mp.get_property_number("duration", 0) * (sliderpos / 100),
                                thumbX,
                                mousethumbY
                            )
							
							
							local chapter = get_chapter(mp.get_property_number("duration", 0) * (sliderpos / 100))
							local hasChapter = not (chapter == nil) and chapter.title and chapter.title ~= "" and not is_timestamp_title(chapter.title)
							local showChapter = user_opts.showchaptertooltip
							local chapterLabel = ""
							
							if hasChapter then
								chapterHeight = slider_lo.tooltip_style
								chapterLabel = chapter.title
							end
							
							local longChapterTitle = chapterLabel:len() >= 30
								
							if hasChapter and showChapter then
								elem_ass:new_event()
								elem_ass:pos(thumbX * r_w + math.floor(thumbfast.width/2), mousethumbY - 20)
								elem_ass:an(5)
								elem_ass:append(slider_lo.tooltip_style)
								elem_ass:append("{\\fs27}")
								ass_append_alpha(elem_ass, slider_lo.alpha, 0)
								elem_ass:append(chapterLabel)
							end	
							
							elem_ass:draw_stop()
                        
						end
                    end
                else
                    if thumbfast.width ~= 0 and thumbfast.height ~= 0 then
                        mp.commandv("script-message-to", "thumbfast", "clear")
                    end
                end
            end

        elseif (element.type == "button") then
			local button_lo = element.layout.button

            local buttontext
            if type(element.content) == "function" then
                buttontext = element.content() -- function objects
            elseif not (element.content == nil) then
                buttontext = element.content -- text objects
            end
			
			buttontext = buttontext:gsub(":%((.?.?.?)%) unknown ", ":%(%1%)")  --gsub("%) unknown %(\"", "")

            local maxchars = element.layout.button.maxchars
            -- 使用consolas字体时1个中文字符大约为1.5个英文字符
            -- local charcount = buttontext:len()-  (buttontext:len()-select(2, buttontext:gsub('[^\128-\193]', '')))/1.5
            local charcount = (buttontext:len() + select(2, buttontext:gsub('[^\128-\193]', ''))*2) / 3
            if not (maxchars == nil) and (charcount > maxchars) then
                local limit = math.max(0, maxchars - 3)
                if (charcount > limit) then
                    while (charcount > limit) do
                        buttontext = buttontext:gsub(".[\128-\191]*$", "")
						charcount = (buttontext:len() + select(2, buttontext:gsub('[^\128-\193]', ''))*2) / 3
                    end
                    buttontext = buttontext .. "..."
                end
            end

            local isButton = element.eventresponder and (
                not (element.eventresponder["mbtn_left_down"] == nil)
                or not (element.eventresponder["mbtn_left_up"] == nil)
            )
            
			local isWcButton = element.content and (
				(element.content == "\238\132\149")
				or (element.content == "\238\132\147")
				or (element.content == "\238\132\148")
				or (element.content == "\238\132\146")
			)
			
			local buttonHovered = mouse_hit(element)
            if isButton and buttonHovered and element.enabled then
                
				
				buttontext = button_lo.hover_style .. buttontext
				
				-- Hover BG Circle	
				local elem_geo = element.layout.geometry
				local bgcircle_style = "{\\rDefault\\blur0\\bord2\\1c&HFFFFFF\\3c&HFFFFFF\\1a&HDC&\\3a&HFF&\\fscx175\\fscy175}"
				local bgcircle_ass = assdraw.ass_new()
				if isWcButton then
					bgcircle_style = "{\\rDefault\\blur0\\bord0\\1c&HFFFFFF\\1a&HDC&\\fscx0\\fscy0}"
				end
				
				bgcircle_ass:merge(style_ass)
				bgcircle_ass:append(bgcircle_style)
				bgcircle_ass:draw_start()
				local r = elem_geo.w / 2
                -- Note: round_rect_cw(x0, y0, x1, y1, r1, r2)
                bgcircle_ass:round_rect_cw(
                    (elem_geo.w / 2) - r, (elem_geo.h / 2) - r - 2,
                    (elem_geo.w / 2) + r, (elem_geo.h / 2) + r - 2,
                    r, nil
                )				
				bgcircle_ass:draw_stop()
				master_ass:merge(bgcircle_ass)
				
				--[[ Hover Glow/Shadow
				local shadow_ass = assdraw.ass_new()
				shadow_ass:merge(style_ass)
				shadow_ass:append("{\\blur5}" .. buttontext .. "{\\blur0}")
				master_ass:merge(shadow_ass) --]]
			end

            elem_ass:append(buttontext)

			-- Tooltip
            if buttonHovered and (not (button_lo.tooltip == nil)) then
                local tx = button_lo.tooltip_geo.x
                local ty = button_lo.tooltip_geo.y
                local labelList = {}
                if type(button_lo.tooltip) == "function" then
                    labelList = button_lo.tooltip()
                else
                    labelList = button_lo.tooltip
                end
                if type(labelList) == "string" then
                    labelList = { labelList }
                end
                if not (type(labelList) == "table") then
                    labelList = {}
                end
                local rowY = ty
                for i, label in ipairs(labelList) do
                    rowY = ty - ((i-1) * splash.buttonTooltipSize)
                    new_ass_node(elem_ass)
                    elem_ass:pos(tx, rowY)
                    elem_ass:an(button_lo.tooltip_an)
                    elem_ass:append(button_lo.tooltip_style)
                    ass_append_alpha(elem_ass, splash.tooltipAlphaTable, 0)
                    elem_ass.scale = 1
                    elem_ass:append(label)
                    elem_ass.scale = 4
                end
                rowY = rowY - splash.buttonTooltipSize

                if not (button_lo.playlist == nil) then
                    local thumbPos = {
                        x = tx,
                        y = rowY,
                        an = button_lo.tooltip_an,
                    }
                    renderPlaylistTooltip(thumbPos, button_lo.playlist, elem_ass)
                end
            end
        end

        master_ass:merge(elem_ass)
    end
end

--
-- Message display
--

-- pos is 1 based
function limited_list(prop, pos)
    local proplist = mp.get_property_native(prop, {})
    local count = #proplist
    if count == 0 then
        return count, proplist
    end

    local fs = tonumber(mp.get_property('options/osd-font-size'))
    local max = math.ceil(osc_param.unscaled_y*0.75 / fs)
    if max % 2 == 0 then
        max = max - 1
    end
    local delta = math.ceil(max / 2) - 1
    local begi = math.max(math.min(pos - delta, count - max + 1), 1)
    local endi = math.min(begi + max - 1, count)

    local reslist = {}
    for i=begi, endi do
        local item = proplist[i]
        item.current = (i == pos) and true or nil
        table.insert(reslist, item)
    end
    return count, reslist
end

function get_playlist()
    local pos = mp.get_property_number('playlist-pos', 0) + 1
    local count, limlist = limited_list('playlist', pos)
    if count == 0 then
        return 'Empty playlist.'
    end

    local message = string.format('Playlist [%d/%d]:\n', pos, count)
    for i, v in ipairs(limlist) do
        local title = v.title
        local _, filename = utils.split_path(v.filename)
        if title == nil then
            title = filename
        end
        message = string.format('%s %s %s\n', message,
            (v.current and '●' or '○'), title)
    end
    return message
end

function get_chapterlist()
    local pos = mp.get_property_number('chapter', 0) + 1
    local count, limlist = limited_list('chapter-list', pos)
    if count == 0 then
        return 'No chapters.'
    end

    local message = string.format('Chapters [%d/%d]:\n', pos, count)
    for i, v in ipairs(limlist) do
        local time = mp.format_time(v.time)
        local title = v.title
        if title == nil then
            title = string.format('Chapter %02d', i)
        end
        message = string.format('%s[%s] %s %s\n', message, time,
            (v.current and '●' or '○'), title)
    end
    return message
end

function show_message(text, duration)

    --print("text: "..text.."   duration: " .. duration)
    if duration == nil then
        duration = tonumber(mp.get_property("options/osd-duration")) / 1000
    elseif not type(duration) == "number" then
        print("duration: " .. duration)
    end

    -- cut the text short, otherwise the following functions
    -- may slow down massively on huge input
    text = string.sub(text, 0, 4000)

    -- replace actual linebreaks with ASS linebreaks
    text = string.gsub(text, "\n", "\\N")

    state.message_text = text

    if not state.message_hide_timer then
        state.message_hide_timer = mp.add_timeout(0, request_tick)
    end
    state.message_hide_timer:kill()
    state.message_hide_timer.timeout = duration
    state.message_hide_timer:resume()
    request_tick()
end

function render_message(ass)
    if state.message_hide_timer and state.message_hide_timer:is_enabled() and
       state.message_text
    then
        local _, lines = string.gsub(state.message_text, "\\N", "")

        local fontsize = tonumber(mp.get_property("options/osd-font-size"))
        local outline = tonumber(mp.get_property("options/osd-border-size"))
        local maxlines = math.ceil(osc_param.unscaled_y*0.75 / fontsize)
        local counterscale = osc_param.playresy / osc_param.unscaled_y

        fontsize = fontsize * counterscale / math.max(0.65 + math.min(lines/maxlines, 1), 1)
        outline = outline * counterscale / math.max(0.75 + math.min(lines/maxlines, 1)/2, 1)

        local style = "{\\bord" .. outline .. "\\fs" .. fontsize .. "}"


        ass:new_event()
        ass:append(style .. state.message_text)
    else
        state.message_text = nil
    end
end

--
-- Initialisation and Layout
--

function new_element(name, type)
    elements[name] = {}
    elements[name].type = type

    -- add default stuff
    elements[name].eventresponder = {}
    elements[name].visible = true
    elements[name].enabled = true
    elements[name].softrepeat = false
    elements[name].styledown = (type == "button")
    elements[name].state = {}

    if (type == "slider") then
        elements[name].slider = {min = {value = 0}, max = {value = 100}}
    end


    return elements[name]
end

function add_layout(name)
    if not (elements[name] == nil) then
        -- new layout
        elements[name].layout = {}

        -- set layout defaults
        elements[name].layout.layer = 50
        elements[name].layout.alpha = {[1] = 0, [2] = 255, [3] = 255, [4] = 255}

        if (elements[name].type == "button") then
            elements[name].layout.button = {
                maxchars = nil,
				hover_style = osc_styles.buttonHovered,
				playlist = nil,
            }
        elseif (elements[name].type == "slider") then
            -- slider defaults
            elements[name].layout.slider = {
                seekbar_offset = 0,
				border = 1,
                gap = 1,
                nibbles_top = true,
                nibbles_bottom = true,
                stype = "slider",
                adjust_tooltip = true,
                tooltip_style = "",
                tooltip_an = 2,
                alpha = {[1] = 0, [2] = 255, [3] = 88, [4] = 255},
            }
        elseif (elements[name].type == "box") then
            elements[name].layout.box = {radius = 0, hexagon = false}
        end

        return elements[name].layout
    else
        msg.error("Can't add_layout to element \""..name.."\", doesn't exist.")
    end
end

-- Window Controls
function window_controls(topbar)
    local wc_geo = {
        x = 0,
	-- -2去除默认情况下上方和边框之间的4px间隔
        y = 48 + user_opts.barmargin -2,
        an = 1,
        w = osc_param.playresx,
        h = 48,
    }

    local alignment = window_controls_alignment()
    local controlbox_w = window_control_box_width
    local titlebox_w = wc_geo.w - controlbox_w

    -- Default alignment is "right"
    local controlbox_left = wc_geo.w - controlbox_w
    local titlebox_left = wc_geo.x
    local titlebox_right = wc_geo.w - controlbox_w

    if alignment == "left" then
        controlbox_left = wc_geo.x
        titlebox_left = wc_geo.x + controlbox_w
        titlebox_right = wc_geo.w
    end

    add_area("window-controls",
             get_hitbox_coords(controlbox_left, wc_geo.y, wc_geo.an,
                               controlbox_w, wc_geo.h))

    local lo

    -- Background Bar
    new_element("wcbar", "box")
    lo = add_layout("wcbar")
    lo.geometry = wc_geo
    lo.layer = 10
    lo.style = osc_styles.wcBar
    lo.alpha[1] = user_opts.boxalpha

    local button_y = wc_geo.y - (wc_geo.h - 14)
    local first_geo =
        {x = controlbox_left + 5, y = button_y, an = 4, w = 25, h = 25}
    local second_geo =
        {x = controlbox_left + 30, y = button_y, an = 4, w = 25, h = 25}
    local third_geo =
        {x = controlbox_left + 55, y = button_y, an = 4, w = 25, h = 25}

    -- Window control buttons use symbols in the custom mpv osd font
    -- because the official unicode codepoints are sufficiently
    -- exotic that a system might lack an installed font with them,
    -- and libass will complain that they are not present in the
    -- default font, even if another font with them is available.

    -- Close: ??
    ne = new_element("close", "button")
    ne.content = "\238\132\149"
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("quit") end
    lo = add_layout("close")
    lo.geometry = alignment == "left" and first_geo or third_geo
    lo.style = osc_styles.wcButtons
	lo.layer = 11

    -- Minimize: ??
    ne = new_element("minimize", "button")
    ne.content = "\238\132\146"
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("cycle", "window-minimized") end
    lo = add_layout("minimize")
    lo.geometry = alignment == "left" and second_geo or first_geo
    lo.style = osc_styles.wcButtons
	lo.layer = 11

    -- Maximize: ?? /??
    ne = new_element("maximize", "button")
    if state.maximized or state.fullscreen then
        ne.content = "\238\132\148"
    else
        ne.content = "\238\132\147"
    end
    ne.eventresponder["mbtn_left_up"] =
        function ()
            if state.fullscreen then
                mp.commandv("cycle", "fullscreen")
            else
                mp.commandv("cycle", "window-maximized")
            end
        end
    lo = add_layout("maximize")
    lo.geometry = alignment == "left" and third_geo or second_geo
    lo.style = osc_styles.wcButtons
	lo.layer = 11

    -- deadzone below window controls
    local sh_area_y0, sh_area_y1
    sh_area_y0 = user_opts.barmargin
    sh_area_y1 = (wc_geo.y + (wc_geo.h / 2)) +
                 get_align(1 - (2 * user_opts.deadzonesize),
                 osc_param.playresy - (wc_geo.y + (wc_geo.h / 2)), 0, 0)
    add_area("showhide_wc", wc_geo.x, sh_area_y0, wc_geo.w, sh_area_y1)

    
	if topbar then
        -- The title is already there as part of the top bar
        return
    else
        -- Apply boxvideo margins to the control bar
        osc_param.video_margins.t = wc_geo.h / osc_param.playresy
    end

    -- Window Title
    ne = new_element("wctitle", "button")
    ne.content = function ()
    local title = mp.command_native({"expand-text", user_opts.title})
        -- escape ASS, and strip newlines and trailing slashes
        title = title:gsub("\\n", " "):gsub("\\$", ""):gsub("{","\\{")
        return not (title == "") and title or "mpv"
    end
    local left_pad = titlebox_w / 2 - 52
    local right_pad = 10
    lo = add_layout("wctitle")
    -- -3用来解决由于字体从24变为18后字体太靠下的问题
    lo.geometry =
        { x = titlebox_left + left_pad, y = wc_geo.y - wc_geo.y / 4 - 5, an = 1,
          w = titlebox_w, h = wc_geo.h }
    lo.style = string.format("%s{\\clip(%f,%f,%f,%f)}",
        osc_styles.wcTitle,
        titlebox_left + left_pad, wc_geo.y - wc_geo.h,
        titlebox_right - right_pad , wc_geo.y + wc_geo.h)
	lo.layer = 11
	lo.button.maxchars = user_opts.wcmaxchars
	
	-- Title Extension
	
	ne = new_element("wcextension", "button")
	lo = add_layout("wcextension")
	ne.content = string.upper(string.sub(mp.get_property_osd("file-format"), 1, 3))
	lo.geometry =
        { x = titlebox_left + left_pad - 40	, y = wc_geo.y - wc_geo.y / 4 - 4, an = 1,
          w = titlebox_w, h = wc_geo.h }
    
	lo.style = osc_styles.wcExt
	lo.layer = 11

	-- Splash logo		 
	
	ne = new_element("splashlogo", "button")
	lo = add_layout("splashlogo")
	ne.content = '\xEE\x80\xB7'
	lo.geometry =
        { x = 2, y = 6, an = 7,
          w = wc_geo.w / 10, h = wc_geo.h}
    
	lo.style = osc_styles.splashlogo
	lo.layer = 11
	lo.alpha[1] = user_opts.buttonalpha
	
	ne = new_element("splashtext", "button")
	lo = add_layout("splashtext")
	ne.content = "splash"
	lo.geometry =
        { x = 48, y = 12, an = 7,
          w = wc_geo.w / 10, h = wc_geo.h}
    
	lo.style = osc_styles.splashtext
	lo.layer = 11
	lo.alpha[1] = user_opts.buttonalpha
	
	add_area("window-controls-title",
             titlebox_left, 0, titlebox_right, wc_geo.h)
end

--
-- Layouts
--

local layouts = {}

-- Default layout
layouts["default"] = function ()

    local osc_geo = {
        w = osc_param.playresx+1,    -- width
        h = 90,    -- height
        r = 0,     -- corner-radius
        p = 0,     -- padding
    }

    -- make sure the OSC actually fits into the video
    if (osc_param.playresx+1 <= (osc_geo.w + (2 * osc_geo.p))) then
        osc_param.playresy = (osc_geo.w+(2*osc_geo.p))/osc_param.display_aspect
        osc_param.playresx = osc_param.playresy * osc_param.display_aspect
    end

    -- position of the controller according to video aspect and valignment
    local posX = math.floor(get_align(user_opts.halign, osc_param.playresx,
        osc_geo.w, 0))
    local posY = math.floor(get_align(user_opts.valign, osc_param.playresy,
        osc_geo.h, 0))

    -- position offset for contents aligned at the borders of the box
    local pos_offsetX = (osc_geo.w - (2*osc_geo.p)) / 2
    local pos_offsetY = (osc_geo.h - (2*osc_geo.p)) / 2

    osc_param.areas = {} -- delete areas

    -- area for active mouse input
    add_area("input", get_hitbox_coords(posX, posY, 5, osc_geo.w, osc_geo.h))

    -- area for show/hide
    local sh_area_y0, sh_area_y1
    if user_opts.valign > 0 then
        -- deadzone above OSC
        sh_area_y0 = get_align(-1 + (2*user_opts.deadzonesize),
            posY - (osc_geo.h / 2), 0, 0)
        sh_area_y1 = osc_param.playresy
    else
        -- deadzone below OSC
        sh_area_y0 = 0
        sh_area_y1 = (posY + (osc_geo.h / 2)) +
            get_align(1 - (2*user_opts.deadzonesize),
            osc_param.playresy - (posY + (osc_geo.h / 2)), 0, 0)
    end
    add_area("showhide", 0, sh_area_y0, osc_param.playresx, sh_area_y1)

    -- fetch values
    local osc_w, osc_h, osc_r, osc_p =
        osc_geo.w, osc_geo.h, osc_geo.r, osc_geo.p

    local lo


    --
    -- Background box
    --

    new_element("bgbox", "box")
    lo = add_layout("bgbox")

    lo.geometry = {x = posX, y = posY + 15, an = 5, w = osc_w, h = osc_h - 30}
    lo.layer = 9
    lo.style = osc_styles.bgBox
    lo.alpha[1] = user_opts.boxalpha
    lo.box.radius = osc_r

    --
    -- Darker background box
    --

    new_element("bgbox2", "box")
    lo = add_layout("bgbox2")

    lo.geometry = {x = posX, y = posY - 30, an = 5, w = osc_w, h = 30}
    lo.layer = 10
    lo.style = osc_styles.bgBox2
    lo.alpha[1] = user_opts.boxalpha
    lo.box.radius = osc_r

    --
    -- Title row
    --
	local refX = posX - pos_offsetX - osc_p
	local refY = posY - pos_offsetY - osc_p

	
    --
    -- Seekbar
    --
	geo = {x = refX + osc_geo.w/2 - 55 , y = refY + 16, an = 5, w = osc_geo.w - 130, h = 6}
 
    new_element("bgbar1", "box")
    lo = add_layout("bgbar1")
 
    lo.geometry = geo
    lo.layer = 10
    lo.style = osc_styles.bgSeekbar
	lo.alpha[1] = user_opts.seekrangealpha
    
	lo = add_layout("seekbar")
    lo.geometry = {x = refX + osc_geo.w/2 - 55, y = refY + 16, an = 5, w = osc_geo.w - 130, h = 16}
	lo.style = osc_styles.fgSeekbar
    lo.slider.border = 0
    lo.slider.gap = 0
	lo.slider.seekbar_offset = 10
    lo.slider.tooltip_style = osc_styles.tpSeekbar
    lo.slider.tooltip_an = 2
    lo.slider.stype = user_opts["seekbarstyle"]
    lo.slider.rtype = user_opts["seekrangestyle"]
	lo.alpha[1] = user_opts.boxalpha

    
	--[[ seekbar-control divider
	geo ={x = refX + osc_geo.w / 2 , y = refY + 28 , an = 5, w = osc_geo.w - 20, h = 1}
    new_element("bgbar2", "box")
    lo = add_layout("bgbar2")
    lo.geometry = geo
    lo.layer = 13
    lo.style = osc_styles.divA
    lo.alpha[1] = math.min(255, user_opts.boxalpha + (255 - user_opts.boxalpha)*0.05)--]]

	-- s32Button
	-- lo.style = "{\\blur0\\bord0\\1c&HCAC1B8\\3c&HFFFFFF\\fs30\\fnMaterial Icons Round}"

	-- buttons
	
	--[[lo = add_layout("skipback")
    lo.geometry = {x = refX + 48, y = refY + 47 , an = 5, w = 26, h = 30}
    lo.style = osc_styles.s24Button	
	
    lo = add_layout("skipfrwd")
    lo.geometry = {x = refX + 72, y = refY + 47 , an = 5, w = 26, h = 30}
    lo.style = osc_styles.s24Button	--]]
		
	-- Center
	
	lo = add_layout("playpause")
    lo.geometry = {x = refX + osc_geo.w / 2 + 1, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = "{\\blur0\\bord0\\fscx122\\1c&H" .. splash.brightButtonColor .. "\\3c&HFFFFFF\\fs30\\fnMaterial Icons Round}"
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha
	
    lo = add_layout("effects")
    lo.geometry = {x = refX + osc_geo.w / 2 - 150, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = "{\\blur0\\bord0\\fscy90\\1c&H" .. splash.brightButtonColor .. "\\3c&HFFFFFF\\fs22\\fnMaterial Icons Round}"
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha
	
    lo = add_layout("stop")
    lo.geometry = {x = refX + osc_geo.w / 2 - 100, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = "{\\blur0\\bord0\\1c&H" .. splash.brightButtonColor .. "\\3c&HFFFFFF\\fs28\\fnMaterial Icons Round}"
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha

    lo = add_layout("pl_prev")
    lo.geometry = {x = refX + osc_geo.w / 2 - 50, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = "{\\blur0\\bord0\\fscx125\\1c&H" .. splash.brightButtonColor .. "\\3c&HFFFFFF\\fs30\\fnMaterial Icons Round}"
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha

    lo = add_layout("pl_next")
    lo.geometry = {x = refX + osc_geo.w / 2 + 51, y = refY + 60, an = 5, w = 26, h = 30}
	lo.style = "{\\blur0\\bord0\\fscx125\\1c&H" .. splash.brightButtonColor .. "\\3c&HFFFFFF\\fs30\\fnMaterial Icons Round}"
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha

	lo = add_layout("open")
    lo.geometry = {x = refX + osc_geo.w / 2 + 101, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = "{\\blur0\\bord0\\fscy110\\fscx85\\1c&H" .. splash.brightButtonColor .. "\\3c&HFFFFFF\\fr-90\\fs30\\fnMaterial Icons Round}"
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha
		
	lo = add_layout("playlist")
    lo.geometry = {x = refX + osc_geo.w / 2 + 150, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = "{\\blur0\\bord0\\fscx110\\1c&H" .. splash.brightButtonColor .. "\\3c&HFFFFFF\\fs21\\fnMaterial Icons Round}"
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha
	
	-- Left
	
	lo = add_layout("info")
    lo.geometry = {x = refX + 34, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = osc_styles.s24Button
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha
	
	lo = add_layout("screenshot")
    lo.geometry = {x = refX + 85, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = osc_styles.s24Button
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha
	
	lo = add_layout("cy_audio")
    lo.geometry = {x = refX + 135, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = "{\\blur0\\bord0\\1c&H" .. splash.dimButtonColor .. "\\3c&HFFFFFF\\fs28\\fnMaterial Icons Round}"
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha
	
	lo = add_layout("cy_sub")
    lo.geometry = {x = refX + 185, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = "{\\blur0\\bord0\\1c&H" .. splash.dimButtonColor .. "\\3c&HFFFFFF\\fs21\\fnMaterial Icons Round}"
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha
	
	-- Right
	
	lo = add_layout("volume")
    lo.geometry = {x = refX + osc_geo.w - 198, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = "{\\blur0\\bord0\\1c&H" .. splash.dimButtonColor .. "\\3c&HFFFFFF\\fs28\\fnMaterial Icons Round}"
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha
	
	lo = add_layout("repeat")
    lo.geometry = {x = refX + osc_geo.w - 246, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = "{\\blur0\\bord0\\1c&H" .. splash.dimButtonColor .. "\\3c&HFFFFFF\\fry180\\fs24\\fnMaterial Icons Round}"
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha
	
	lo = add_layout("shuffle")
    lo.geometry = {x = refX + osc_geo.w - 296, y = refY + 60, an = 5, w = 26, h = 30}
    lo.style = "{\\blur0\\bord0\\1c&H" .. splash.dimButtonColor .. "\\3c&HFFFFFF\\fs24\\fnMaterial Icons Round}"
	lo.layer = 13
	lo.alpha[1] = user_opts.buttonalpha
	

	-- Volume bar
	vol_geo = {x = refX + osc_geo.w - 95 , y = refY + 61, an = 5, w = 150, h = 5}
    new_element("volbarbg", "box")
    lo = add_layout("volbarbg")
    lo.geometry = vol_geo
    lo.layer = 10
    lo.style = osc_styles.bgSeekbar
	lo.alpha[1] = user_opts.seekrangealpha
    
	lo = add_layout("volbar")
    lo.geometry = {x = refX + osc_geo.w - 95, y = refY + 61, an = 5, w = 150, h = 4}
	lo.style = osc_styles.fgSeekbar
    lo.slider.border = 0
    lo.slider.gap = 0
	lo.slider.seekbar_offset = 0
    lo.slider.tooltip_style = osc_styles.tpSeekbar
    lo.slider.tooltip_an = 2
	lo.slider.stype = user_opts["seekbarstyle"]
    lo.slider.rtype = user_opts["seekrangestyle"]
	lo.alpha[1] = user_opts.boxalpha
	

	-- Time
	lo = add_layout("tc_both")
    lo.geometry = {x = refX + osc_geo.w - 58, y = refY + 14, an = 5, w = 64, h = 30}
    lo.style = osc_styles.s12Button
	lo.alpha[1] = 25
	
	--[[ Media title
	lo = add_layout("title")
    lo.geometry = {x = refX + 310  , y = refY + 47 , an = 4, w = 370, h = 20}
    lo.style = osc_styles.s16Button	
    lo.button.maxchars = user_opts.boxmaxchars

    lo = add_layout("cy_audio")
    lo.geometry = {x = refX + osc_geo.w - 135, y = refY + 47, an = 4, w = 64, h = 30}
    lo.style = osc_styles.cyButton	

    lo = add_layout("cy_sub")
    lo.geometry = {x = refX + osc_geo.w - 70, y = refY + 47, an = 4, w = 64, h = 30}
    lo.style = osc_styles.cyButton
	--]]
end

-- Validate string type user options
function validate_user_opts()
    if layouts[user_opts.layout] == nil then
        msg.warn("Invalid setting \""..user_opts.layout.."\" for layout")
        user_opts.layout = "default"
    end

    if user_opts.seekbarstyle ~= "bar" and
       user_opts.seekbarstyle ~= "diamond" and
       user_opts.seekbarstyle ~= "knob" then
        msg.warn("Invalid setting \"" .. user_opts.seekbarstyle
            .. "\" for seekbarstyle")
        user_opts.seekbarstyle = "bar"
    end

    if user_opts.seekrangestyle ~= "bar" and
       user_opts.seekrangestyle ~= "line" and
       user_opts.seekrangestyle ~= "slider" and
       user_opts.seekrangestyle ~= "inverted" and
       user_opts.seekrangestyle ~= "none" then
        msg.warn("Invalid setting \"" .. user_opts.seekrangestyle
            .. "\" for seekrangestyle")
        user_opts.seekrangestyle = "inverted"
    end

    if user_opts.seekrangestyle == "slider" and
       user_opts.seekbarstyle == "bar" then
        msg.warn("Using \"slider\" seekrangestyle together with \"bar\" seekbarstyle is not supported")
        user_opts.seekrangestyle = "inverted"
    end

    if user_opts.windowcontrols ~= "auto" and
       user_opts.windowcontrols ~= "yes" and
       user_opts.windowcontrols ~= "no" then
        msg.warn("windowcontrols cannot be \"" ..
                user_opts.windowcontrols .. "\". Ignoring.")
        user_opts.windowcontrols = "auto"
    end
    if user_opts.windowcontrols_alignment ~= "right" and
       user_opts.windowcontrols_alignment ~= "left" then
        msg.warn("windowcontrols_alignment cannot be \"" ..
                user_opts.windowcontrols_alignment .. "\". Ignoring.")
        user_opts.windowcontrols_alignment = "right"
    end
end

function update_options(list)
    validate_user_opts()
    request_tick()
    visibility_mode(user_opts.visibility, true)
    request_init()
end

-- OSC INIT
function osc_init()
    msg.debug("osc_init")

    -- set canvas resolution according to display aspect and scaling setting
    local baseResY = 720
    local display_w, display_h, display_aspect = mp.get_osd_size()
    local scale = 1

    if (mp.get_property("video") == "no") then -- dummy/forced window
        scale = user_opts.scaleforcedwindow
    elseif state.fullscreen then
        scale = user_opts.scalefullscreen
    else
        scale = user_opts.scalewindowed
    end

    if user_opts.vidscale then
        osc_param.unscaled_y = baseResY
    else
        osc_param.unscaled_y = display_h
    end
    osc_param.playresy = osc_param.unscaled_y / scale
    if (display_aspect > 0) then
        osc_param.display_aspect = display_aspect
    end
    osc_param.playresx = osc_param.playresy * osc_param.display_aspect

    -- stop seeking with the slider to prevent skipping files
    state.active_element = nil

    osc_param.video_margins = {l = 0, r = 0, t = 0, b = 0}

    elements = {}

    -- some often needed stuff
    local pl_count = mp.get_property_number("playlist-count", 0)
    local have_pl = (pl_count > 1)
    local pl_pos = mp.get_property_number("playlist-pos", 0) + 1
    local have_ch = (mp.get_property_number("chapters", 0) > 0)
    local loop = mp.get_property("loop-playlist", "no")

    local ne

    -- title
    ne = new_element("title", "button")

    ne.content = function ()
        local title = mp.command_native({"expand-text", user_opts.title})
        -- escape ASS, and strip newlines and trailing slashes
        title = title:gsub("\\n", " "):gsub("\\$", ""):gsub("{","\\{")
        return not (title == "") and title or "mpv"
    end

    ne.eventresponder["mbtn_left_up"] = function ()
        local title = mp.get_property_osd("media-title")
        if (have_pl) then
            title = string.format("[%d/%d] %s", countone(pl_pos - 1),
                                  pl_count, title)
        end
        show_message(title)
    end

    ne.eventresponder["mbtn_right_up"] =
        function () show_message(mp.get_property_osd("filename")) end

    -- playlist buttons

    -- prev
    ne = new_element("pl_prev", "button")

    ne.content = '\xEE\x81\x85'
    ne.enabled = (pl_pos > 1) or (loop ~= "no")
    ne.eventresponder["mbtn_left_up"] =
        function ()
            mp.commandv("playlist-prev", "weak")
			--show_message(get_playlist(), 3)
        end
    ne.eventresponder["shift+mbtn_left_up"] =
        function () show_message(get_playlist(), 3)
		end
    ne.eventresponder["mbtn_right_up"] =
        function () show_message(get_playlist(), 3) end

    --next
    ne = new_element("pl_next", "button")

	ne.content = '\xEE\x81\x84'
    ne.enabled = (have_pl and (pl_pos < pl_count)) or (loop ~= "no")
    ne.eventresponder["mbtn_left_up"] =
        function ()
            mp.commandv("playlist-next", "weak")
			--show_message(get_playlist(), 3)
        end
    ne.eventresponder["shift+mbtn_left_up"] =
        function () show_message(get_playlist(), 3) end
    ne.eventresponder["mbtn_right_up"] =
        function () show_message(get_playlist(), 3) end


    -- big buttons

    --playpause
    ne = new_element("playpause", "button")

    ne.content = function ()
        if mp.get_property("pause") == "yes" then
			return ('\xEE\x80\xB7')
        else 
			return ('\xEE\x80\xB4')
        end
    end
    ne.eventresponder["mbtn_left_up"] =
		function () mp.commandv("osd-auto", "cycle", "pause") end
	
	-- stop
    ne = new_element("stop", "button")
	ne.content = '\xEE\x81\x87'
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("stop") end

	-- shaders/effect
    ne = new_element("effects", "button")
	ne.content = '\xEE\x90\xA9'
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("script-binding", "stats/display-stats-toggle") end

	-- open file
    ne = new_element("open", "button")
	ne.content = '\xEE\xA3\xBB'
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("script-message", "mpv.net", "open-files") end
		
	-- playlist
    ne = new_element("playlist", "button")
	ne.content = '\xEE\x89\x81'
    ne.eventresponder["mbtn_left_up"] =
        function () mp.command("show-text ${playlist}") end
		
	-- info
    ne = new_element("info", "button")
	ne.content = '\x69\x6E\x66\x6F'
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("script-binding", "stats/display-stats-toggle") end

	-- screenshot
    ne = new_element("screenshot", "button")
	ne.content = '\xEE\x8E\xB0'
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("osd-auto", "screenshot") end
		
	-- cycle audio
    ne = new_element("cy_audio", "button")
	ne.content = '\xEE\x81\x8E'
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("osd-auto", "cycle", "audio") end
		
	-- cycle subtitles
    ne = new_element("cy_sub", "button")
	ne.content = '\xEE\x89\x93'
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("osd-auto", "cycle", "sub") end
		
		
	-- volume icon
    ne = new_element("volume", "button")
    ne.content = function()
        local volume = mp.get_property_number("volume", 0)
        local mute = mp.get_property_native("mute")
        if volume == 0 or mute then
            return '\xEE\x81\x8F'
        else
            return '\xEE\x81\x90'
        end
    end
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("osd-auto", "cycle", "mute") end
		
		
	-- repeat
    ne = new_element("repeat", "button")
	ne.content = function()
		local loop = mp.get_property("loop")
        if (loop == "inf") then
			return '{\\1c&H5624FF}\xEE\x81\x82'
        else
            return '\xEE\x81\x82'
        end
    end
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("osd-auto", "cycle-values", "loop", "yes", "no") 
		end
		
	-- shuffle
    ne = new_element("shuffle", "button")
	ne.content = function()
		local shuffle = mp.get_property("shuffle")
        if (shuffle == "yes") then
			return '{\\1c&H5624FF}\xEE\x81\x83'
        else
            return '\xEE\x81\x83'
        end
    end
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("osd-auto", "cycle", "shuffle") end


	----------------------------------------------------------

    --skipback
    ne = new_element("skipback", "button")

    ne.softrepeat = true
    ne.content = "\238\128\132"
    ne.eventresponder["mbtn_left_down"] =
        function () mp.commandv("seek", -5, "relative", "keyframes") end
    ne.eventresponder["shift+mbtn_left_down"] =
        function () mp.commandv("frame-back-step") end
    ne.eventresponder["mbtn_right_down"] =
        function () mp.commandv("seek", -30, "relative", "keyframes") end

    --skipfrwd
    ne = new_element("skipfrwd", "button")

    ne.softrepeat = true
    ne.content = "\238\128\133"
    ne.eventresponder["mbtn_left_down"] =
        function () mp.commandv("seek", 10, "relative", "keyframes") end
    ne.eventresponder["shift+mbtn_left_down"] =
        function () mp.commandv("frame-step") end
    ne.eventresponder["mbtn_right_down"] =
        function () mp.commandv("seek", 60, "relative", "keyframes") end

    --ch_prev
    ne = new_element("ch_prev", "button")

    ne.enabled = have_ch
    ne.content = "\238\132\132"
    ne.eventresponder["mbtn_left_up"] =
        function ()
            mp.commandv("add", "chapter", -1)
            show_message(get_chapterlist(), 3)
        end
    ne.eventresponder["shift+mbtn_left_up"] =
        function () show_message(get_chapterlist(), 3) end
    ne.eventresponder["mbtn_right_up"] =
        function () show_message(get_chapterlist(), 3) end

    --ch_next
    ne = new_element("ch_next", "button")

    ne.enabled = have_ch
    ne.content = "\238\132\133"
    ne.eventresponder["mbtn_left_up"] =
        function ()
            mp.commandv("add", "chapter", 1)
            show_message(get_chapterlist(), 3)
        end
    ne.eventresponder["shift+mbtn_left_up"] =
        function () show_message(get_chapterlist(), 3) end
    ne.eventresponder["mbtn_right_up"] =
        function () show_message(get_chapterlist(), 3) end

    --

    --tog_fs
    ne = new_element("tog_fs", "button")
    ne.content = function ()
        if (state.fullscreen) then
            return ("\238\132\137")
        else
            return ("\238\132\136")
        end
    end
    ne.eventresponder["mbtn_left_up"] =
        function () mp.commandv("cycle", "fullscreen") end

    --seekbar
    ne = new_element("seekbar", "slider")

    ne.enabled = not (mp.get_property("percent-pos") == nil)
    ne.slider.markerF = function ()
        local duration = mp.get_property_number("duration", nil)
        if not (duration == nil) then
            local chapters = mp.get_property_native("chapter-list", {})
            local markers = {}
            for n = 1, #chapters do
                markers[n] = (chapters[n].time / duration * 100)
            end
            return markers
        else
            return {}
        end
    end
    ne.slider.posF =
        function () return mp.get_property_number("percent-pos", nil) end
    ne.slider.tooltipF = function (pos)
        local duration = mp.get_property_number("duration", nil)
        if not ((duration == nil) or (pos == nil)) then
            possec = duration * (pos / 100)
            return mp.format_time(possec)
        else
            return ""
        end
    end
    ne.slider.seekRangesF = function()
        if user_opts.seekrangestyle == "none" then
            return nil
        end
        local cache_state = state.cache_state
        if not cache_state then
            return nil
        end
        local duration = mp.get_property_number("duration", nil)
        if (duration == nil) or duration <= 0 then
            return nil
        end
        local ranges = cache_state["seekable-ranges"]
        if #ranges == 0 then
            return nil
        end
        local nranges = {}
        for _, range in pairs(ranges) do
            nranges[#nranges + 1] = {
                ["start"] = 100 * range["start"] / duration,
                ["end"] = 100 * range["end"] / duration,
            }
		end
		nranges = {}
		return nranges
    end
    ne.eventresponder["mouse_move"] = --keyframe seeking when mouse is dragged
        function (element)
            -- mouse move events may pile up during seeking and may still get
            -- sent when the user is done seeking, so we need to throw away
            -- identical seeks
            local seekto = get_slider_value(element)
            if (element.state.lastseek == nil) or
                (not (element.state.lastseek == seekto)) then
                    local flags = "absolute-percent"
                    if not user_opts.seekbarkeyframes then
                        flags = flags .. "+exact"
                    end
                    mp.commandv("seek", seekto, flags)
                    element.state.lastseek = seekto
            end

        end
    ne.eventresponder["mbtn_left_down"] = --exact seeks on single clicks
        function (element) mp.commandv("seek", get_slider_value(element),
            "absolute-percent", "exact") end
    ne.eventresponder["reset"] =
        function (element) element.state.lastseek = nil end
		
		
	--volume bar
    ne = new_element("volbar", "slider")

    ne.enabled = not state.has_audio
    ne.slider.markerF = function ()
			return {}
    end
    ne.slider.posF =
        function () return mp.get_property_number("volume", 0) end
    
	ne.slider.tooltipF = nil
    ne.slider.seekRangesF = function()
			return nil
    end
    
	ne.eventresponder["mouse_move"] = --keyframe seeking when mouse is dragged
        function (element)
            -- mouse move events may pile up during seeking and may still get
            -- sent when the user is done seeking, so we need to throw away
            -- identical seeks
			local volto = get_slider_value(element)
            if (element.state.lastvol == nil) or
                (not (element.state.lastvol == volto)) then
					mp.commandv("osd-auto", "set", "volume", volto)
					element.state.lastvol = volto
			end
        end
    
	ne.eventresponder["mbtn_left_down"] = --exact seeks on single clicks
        function (element) mp.commandv("osd-auto", "set", "volume", get_slider_value(element)) end
	
	ne.eventresponder["wheel_up_press"] = --scroll to change volume
            function () mp.commandv("osd-auto", "add", "volume", 5) end
	
	ne.eventresponder["wheel_down_press"] = --scroll to change volume
            function () mp.commandv("osd-auto", "add", "volume", -5) end
	
	ne.eventresponder["reset"] =
        function (element) element.state.lastvol = nil end

	-- tc_both (current pos/total time)
    ne = new_element("tc_both", "button")

    ne.visible = (mp.get_property_number("duration", 0) > 0)
    ne.content = function ()
		if state.tc_ms then
			return (mp.get_property_osd("playback-time/full") .. "  /  " .. mp.get_property_osd("duration/full"))
		else
			return (mp.get_property_osd("playback-time") .. "  /  " .. mp.get_property_osd("duration"))
        end
    end
	
    -- cache
    ne = new_element("cache", "button")

    ne.content = function ()
        local cache_state = state.cache_state
        if not (cache_state and cache_state["seekable-ranges"] and
            #cache_state["seekable-ranges"] > 0) then
            -- probably not a network stream
            return ""
        end
        local dmx_cache = cache_state and cache_state["cache-duration"]
        local thresh = math.min(state.dmx_cache * 0.05, 5)  -- 5% or 5s
        if dmx_cache and math.abs(dmx_cache - state.dmx_cache) >= thresh then
            state.dmx_cache = dmx_cache
        else
            dmx_cache = state.dmx_cache
        end
        local min = math.floor(dmx_cache / 60)
        local sec = dmx_cache % 60
        return "Cache: " .. (min > 0 and
            string.format("%sm%02.0fs", min, sec) or
            string.format("%3.0fs", dmx_cache))
    end


    -- load layout
    layouts[user_opts.layout]()

    -- load window controls
    if window_controls_enabled() then
        window_controls(user_opts.layout == "topbar")
    end

    --do something with the elements
    prepare_elements()

    update_margins()
end

function reset_margins()
    if state.using_video_margins then
        for _, opt in ipairs(margins_opts) do
            mp.set_property_number(opt[2], 0.0)
        end
        state.using_video_margins = false
    end
end

function update_margins()
    local margins = osc_param.video_margins

    -- Don't use margins if it's visible only temporarily.
    if (not state.osc_visible) or (get_hidetimeout() >= 0) then
        margins = {l = 0, r = 0, t = 0, b = 0}
    end

    if user_opts.boxvideo then
        -- check whether any margin option has a non-default value
        local margins_used = false

        if not state.using_video_margins then
            for _, opt in ipairs(margins_opts) do
                if mp.get_property_number(opt[2], 0.0) ~= 0.0 then
                    margins_used = true
                end
            end
        end

        if not margins_used then
            for _, opt in ipairs(margins_opts) do
                local v = margins[opt[1]]
                if (v ~= 0) or state.using_video_margins then
                    mp.set_property_number(opt[2], v)
                    state.using_video_margins = true
                end
            end
        end
    else
        reset_margins()
    end
	if mp.del_property then
		mp.set_property_native("user-data/osc/margins",
			string.format("%f,%f,%f,%f", margins.l, margins.r, margins.t, margins.b))
	else
		utils.shared_script_property_set("osc-margins",
			string.format("%f,%f,%f,%f", margins.l, margins.r, margins.t, margins.b))
	end
end

function shutdown()
    reset_margins()
	if mp.del_property then
		mp.set_property_native("user-data/osc/margins", nil)
    else
		utils.shared_script_property_set("osc-margins", nil)
    end
end

--
-- Other important stuff
--


function show_osc()
    -- show when disabled can happen (e.g. mouse_move) due to async/delayed unbinding
    if not state.enabled then return end

    msg.trace("show_osc")
    --remember last time of invocation (mouse move)
    state.showtime = mp.get_time()

    osc_visible(true)

    if (user_opts.fadeduration > 0) then
        state.anitype = nil
    end
end

function hide_osc()
    if not state.enabled then
        -- typically hide happens at render() from tick(), but now tick() is
        -- no-op and won't render again to remove the osc, so do that manually.
        state.osc_visible = false
        render_wipe()
    elseif (user_opts.fadeduration > 0) then
        if not(state.osc_visible == false) then
            state.anitype = "out"
            request_tick()
        end
    else
        osc_visible(false)
    end
end

function osc_visible(visible)
    if state.osc_visible ~= visible then
        state.osc_visible = visible
        update_margins()
    end
    request_tick()
end

function pause_state(name, enabled)
    state.paused = enabled
    request_tick()
end

function cache_state(name, st)
    state.cache_state = st
    request_tick()
end

-- Request that tick() is called (which typically re-renders the OSC).
-- The tick is then either executed immediately, or rate-limited if it was
-- called a small time ago.
function request_tick()
    if state.tick_timer == nil then
        state.tick_timer = mp.add_timeout(0, tick)
    end

    if not state.tick_timer:is_enabled() then
        local now = mp.get_time()
        local timeout = tick_delay - (now - state.tick_last_time)
        if timeout < 0 then
            timeout = 0
        end
        state.tick_timer.timeout = timeout
        state.tick_timer:resume()
    end
end

function mouse_leave()
    if get_hidetimeout() >= 0 then
        hide_osc()
    end
    -- reset mouse position
    state.last_mouseX, state.last_mouseY = nil, nil
    state.mouse_in_window = false
end

function request_init()
    state.initREQ = true
    request_tick()
end

-- Like request_init(), but also request an immediate update
function request_init_resize()
    request_init()
    -- ensure immediate update
    state.tick_timer:kill()
    state.tick_timer.timeout = 0
    state.tick_timer:resume()
end

function render_wipe()
    msg.trace("render_wipe()")
    state.osd:remove()
end

function render()
    msg.trace("rendering")
    local current_screen_sizeX, current_screen_sizeY, aspect = mp.get_osd_size()
    local mouseX, mouseY = get_virt_mouse_pos()
    local now = mp.get_time()

    -- check if display changed, if so request reinit
    if not (state.mp_screen_sizeX == current_screen_sizeX
        and state.mp_screen_sizeY == current_screen_sizeY) then

        request_init_resize()

        state.mp_screen_sizeX = current_screen_sizeX
        state.mp_screen_sizeY = current_screen_sizeY
    end

    -- init management
    if state.initREQ then
        osc_init()
        state.initREQ = false

        -- store initial mouse position
        if (state.last_mouseX == nil or state.last_mouseY == nil)
            and not (mouseX == nil or mouseY == nil) then

            state.last_mouseX, state.last_mouseY = mouseX, mouseY
        end
    end


    -- fade animation
    if not(state.anitype == nil) then

        if (state.anistart == nil) then
            state.anistart = now
        end

        if (now < state.anistart + (user_opts.fadeduration/1000)) then

            if (state.anitype == "in") then --fade in
                osc_visible(true)
                state.animation = scale_value(state.anistart,
                    (state.anistart + (user_opts.fadeduration/1000)),
                    255, 0, now)
            elseif (state.anitype == "out") then --fade out
                state.animation = scale_value(state.anistart,
                    (state.anistart + (user_opts.fadeduration/1000)),
                    0, 255, now)
            end

        else
            if (state.anitype == "out") then
                osc_visible(false)
            end
            state.anistart = nil
            state.animation = nil
            state.anitype =  nil
        end
    else
        state.anistart = nil
        state.animation = nil
        state.anitype =  nil
    end

    --mouse show/hide area
    for k,cords in pairs(osc_param.areas["showhide"]) do
        set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "showhide")
    end
    if osc_param.areas["showhide_wc"] then
        for k,cords in pairs(osc_param.areas["showhide_wc"]) do
            set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "showhide_wc")
        end
    else
        set_virt_mouse_area(0, 0, 0, 0, "showhide_wc")
    end
    do_enable_keybindings()

    --mouse input area
    local mouse_over_osc = false

    for _,cords in ipairs(osc_param.areas["input"]) do
        if state.osc_visible then -- activate only when OSC is actually visible
            set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "input")
        end
        if state.osc_visible ~= state.input_enabled then
            if state.osc_visible then
                mp.enable_key_bindings("input")
            else
                mp.disable_key_bindings("input")
            end
            state.input_enabled = state.osc_visible
        end

        if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
            mouse_over_osc = true
        end
    end

    if osc_param.areas["window-controls"] then
        for _,cords in ipairs(osc_param.areas["window-controls"]) do
            if state.osc_visible then -- activate only when OSC is actually visible
                set_virt_mouse_area(cords.x1, cords.y1, cords.x2, cords.y2, "window-controls")
                mp.enable_key_bindings("window-controls")
            else
                mp.disable_key_bindings("window-controls")
            end

            if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
                mouse_over_osc = true
            end
        end
    end

    if osc_param.areas["window-controls-title"] then
        for _,cords in ipairs(osc_param.areas["window-controls-title"]) do
            if (mouse_hit_coords(cords.x1, cords.y1, cords.x2, cords.y2)) then
                mouse_over_osc = true
            end
        end
    end

    -- autohide
    if not (state.showtime == nil) and (get_hidetimeout() >= 0) then
        local timeout = state.showtime + (get_hidetimeout()/1000) - now
        if timeout <= 0 then
            if (state.active_element == nil) and not (mouse_over_osc) then
                hide_osc()
            end
        else
            -- the timer is only used to recheck the state and to possibly run
            -- the code above again
            if not state.hide_timer then
                state.hide_timer = mp.add_timeout(0, tick)
            end
            state.hide_timer.timeout = timeout
            -- re-arm
            state.hide_timer:kill()
            state.hide_timer:resume()
        end
    end


    -- actual rendering
    local ass = assdraw.ass_new()

    -- Messages
    render_message(ass)

    -- actual OSC
    if state.osc_visible then
        render_elements(ass)
    end

    -- submit
    set_osd(osc_param.playresy * osc_param.display_aspect,
            osc_param.playresy, ass.text)
end

--
-- Eventhandling
--

local function element_has_action(element, action)
    return element and element.eventresponder and
        element.eventresponder[action]
end

function process_event(source, what)
    local action = string.format("%s%s", source,
        what and ("_" .. what) or "")

    if what == "down" or what == "press" then

        for n = 1, #elements do

            if mouse_hit(elements[n]) and
                elements[n].eventresponder and
                (elements[n].eventresponder[source .. "_up"] or
                    elements[n].eventresponder[action]) then

                if what == "down" then
                    state.active_element = n
                    state.active_event_source = source
                end
                -- fire the down or press event if the element has one
                if element_has_action(elements[n], action) then
                    elements[n].eventresponder[action](elements[n])
                end

            end
        end

    elseif what == "up" then

        if elements[state.active_element] then
            local n = state.active_element

            if n == 0 then
                --click on background (does not work)
            elseif element_has_action(elements[n], action) and
                mouse_hit(elements[n]) then

                elements[n].eventresponder[action](elements[n])
            end

            --reset active element
            if element_has_action(elements[n], "reset") then
                elements[n].eventresponder["reset"](elements[n])
            end

        end
        state.active_element = nil
        state.mouse_down_counter = 0

    elseif source == "mouse_move" then

        state.mouse_in_window = true

        local mouseX, mouseY = get_virt_mouse_pos()
        if (user_opts.minmousemove == 0) or
            (not ((state.last_mouseX == nil) or (state.last_mouseY == nil)) and
                ((math.abs(mouseX - state.last_mouseX) >= user_opts.minmousemove)
                    or (math.abs(mouseY - state.last_mouseY) >= user_opts.minmousemove)
                )
            ) then
            show_osc()
        end
        state.last_mouseX, state.last_mouseY = mouseX, mouseY

        local n = state.active_element
        if element_has_action(elements[n], action) then
            elements[n].eventresponder[action](elements[n])
        end
        request_tick()
    end
end


local logo_lines = {
    -- White border
    "{\\c&HFFFFFF&\\p6}m 895 10 b 401 10 0 410 0 905 0 1399 401 1800 895 1800 1390 1800 1790 1399 1790 905 1790 410 1390 10 895 10 {\\p0}",
    -- Purple fill
    "{\\c&H8E348D&\\p6}m 925 42 b 463 42 87 418 87 880 87 1343 463 1718 925 1718 1388 1718 1763 1343 1763 880 1763 418 1388 42 925 42{\\p0}",
    -- Darker fill
    "{\\c&H632462&\\p6}m 1605 828 b 1605 1175 1324 1456 977 1456 631 1456 349 1175 349 828 349 482 631 200 977 200 1324 200 1605 482 1605 828{\\p0}",
    -- White fill
    "{\\c&HFFFFFF&\\p6}m 1296 910 b 1296 1131 1117 1310 897 1310 676 1310 497 1131 497 910 497 689 676 511 897 511 1117 511 1296 689 1296 910{\\p0}",
    -- Triangle
    "{\\c&H691F69&\\p6}m 762 1113 l 762 708 b 881 776 1000 843 1119 911 1000 978 881 1046 762 1113{\\p0}",
}

local splash_lines = {
    -- red bg
    "{\\c&H5E48E7&\\p1}m 10.67 74.27 b 10.67 74.26 10.57 74.24 10.46 74.22 10.35 74.21 10.18 74.18 10.08 74.16 9.97 74.14 9.81 74.12 9.72 74.11 9.45 74.09 8.69 73.9 8.25 73.76 8.19 73.74 8.1 73.71 8.06 73.7 8.02 73.69 7.91 73.65 7.82 73.62 7.74 73.58 7.62 73.54 7.58 73.52 7.53 73.51 7.45 73.47 7.4 73.45 7.34 73.42 7.29 73.4 7.28 73.4 7.26 73.4 7.17 73.36 7.08 73.32 6.99 73.28 6.84 73.21 6.75 73.17 6.66 73.13 6.57 73.08 6.54 73.07 6.51 73.05 6.39 72.99 6.28 72.93 5.89 72.73 5.79 72.67 5.31 72.36 4.82 72.04 4.79 72.01 4.4 71.7 3.62 71.07 2.96 70.39 2.46 69.72 2.37 69.61 2.23 69.42 2.15 69.31 2.07 69.2 2 69.11 2 69.1 2 69.08 1.93 68.98 1.85 68.85 1.77 68.73 1.7 68.62 1.7 68.61 1.7 68.6 1.67 68.55 1.63 68.49 1.56 68.4 1.33 67.96 1.23 67.76 1.21 67.72 1.19 67.67 1.17 67.65 1.16 67.63 1.14 67.58 1.12 67.55 1.11 67.52 1.05 67.39 1 67.28 0.94 67.16 0.9 67.04 0.9 67.02 0.9 66.99 0.88 66.95 0.86 66.91 0.84 66.88 0.8 66.78 0.78 66.7 0.75 66.61 0.71 66.49 0.68 66.43 0.65 66.37 0.62 66.27 0.61 66.21 0.6 66.14 0.57 66.05 0.55 66.01 0.52 65.97 0.49 65.83 0.46 65.7 0.44 65.57 0.4 65.42 0.37 65.37 0.34 65.31 0.32 65.2 0.31 65.08 0.3 64.97 0.27 64.78 0.24 64.64 0.2 64.5 0.16 64.27 0.15 64.12 0.12 63.84 0.07 63.59 0.03 63.58 -0.01 63.57 -0.01 10.73 0.03 10.72 0.07 10.71 0.12 10.47 0.15 10.19 0.17 10.05 0.2 9.88 0.24 9.78 0.28 9.68 0.3 9.57 0.3 9.47 0.3 9.28 0.34 9.1 0.39 9.05 0.41 9.02 0.44 8.93 0.45 8.83 0.46 8.72 0.49 8.62 0.53 8.55 0.57 8.49 0.6 8.38 0.61 8.3 0.62 8.23 0.65 8.12 0.69 8.06 0.73 7.99 0.75 7.92 0.75 7.85 0.75 7.78 0.78 7.68 0.82 7.59 0.86 7.5 0.9 7.4 0.91 7.36 0.92 7.32 0.96 7.24 0.99 7.2 1.02 7.15 1.05 7.09 1.05 7.07 1.05 7.04 1.09 6.95 1.14 6.86 1.19 6.78 1.22 6.69 1.22 6.67 1.22 6.65 1.25 6.6 1.28 6.57 1.3 6.53 1.34 6.47 1.35 6.42 1.37 6.38 1.41 6.3 1.44 6.26 1.47 6.22 1.51 6.15 1.54 6.1 1.59 5.99 1.67 5.86 1.74 5.76 1.78 5.72 1.8 5.68 1.8 5.66 1.8 5.64 1.83 5.59 1.88 5.54 1.92 5.49 1.95 5.45 1.95 5.44 1.95 5.41 2.1 5.18 2.19 5.07 2.31 4.92 2.36 4.84 2.41 4.76 2.43 4.72 2.51 4.62 2.58 4.54 2.65 4.46 2.75 4.35 2.79 4.3 2.88 4.18 3.19 3.81 3.26 3.74 3.29 3.71 3.35 3.64 3.4 3.58 3.45 3.52 3.63 3.35 3.81 3.19 3.99 3.04 4.24 2.82 4.36 2.71 4.48 2.59 4.62 2.49 4.66 2.46 4.7 2.44 4.79 2.38 4.85 2.34 4.91 2.29 4.99 2.23 5.02 2.21 5.06 2.19 5.12 2.15 5.15 2.12 5.18 2.1 5.25 2.06 5.3 2.04 5.35 2.01 5.4 1.98 5.4 1.97 5.42 1.94 5.62 1.82 5.74 1.76 5.78 1.74 5.84 1.71 5.86 1.68 5.89 1.65 5.95 1.61 6.01 1.6 6.06 1.58 6.14 1.54 6.18 1.51 6.22 1.48 6.27 1.45 6.3 1.45 6.32 1.45 6.38 1.42 6.43 1.39 6.47 1.35 6.56 1.31 6.61 1.3 6.67 1.28 6.74 1.24 6.78 1.21 6.82 1.18 6.87 1.15 6.9 1.15 6.92 1.15 6.98 1.12 7.02 1.09 7.07 1.05 7.12 1.02 7.14 1.02 7.15 1.02 7.22 1 7.28 0.96 7.35 0.92 7.45 0.88 7.51 0.86 7.57 0.85 7.65 0.81 7.7 0.78 7.74 0.75 7.8 0.72 7.85 0.72 7.89 0.72 7.97 0.7 8.03 0.67 8.1 0.63 8.21 0.6 8.28 0.59 8.35 0.58 8.47 0.54 8.55 0.51 8.64 0.47 8.76 0.44 8.88 0.43 8.98 0.42 9.1 0.4 9.16 0.37 9.21 0.34 9.35 0.31 9.48 0.3 9.6 0.28 9.77 0.25 9.86 0.22 9.94 0.19 10.12 0.16 10.26 0.14 10.55 0.09 10.7 0.06 10.7 0.02 10.7 -0.01 12.79 -0.01 12.8 0.02 12.81 0.04 12.93 0.07 13.08 0.09 13.22 0.11 13.38 0.14 13.42 0.15 13.47 0.16 13.57 0.18 13.65 0.19 13.72 0.2 13.83 0.22 13.89 0.24 13.94 0.26 14.08 0.29 14.2 0.3 14.33 0.31 14.45 0.34 14.52 0.37 14.58 0.4 14.64 0.42 14.67 0.42 14.76 0.42 15.13 0.52 15.21 0.56 15.25 0.58 15.32 0.6 15.36 0.6 15.4 0.6 15.47 0.62 15.52 0.65 15.6 0.69 15.71 0.73 16.09 0.87 16.22 0.91 16.31 0.95 16.66 1.11 16.76 1.16 16.86 1.2 16.88 1.2 16.9 1.2 16.95 1.22 16.98 1.25 17.02 1.28 17.05 1.3 17.06 1.3 17.07 1.3 17.15 1.33 17.22 1.37 17.3 1.4 17.46 1.48 17.58 1.53 17.69 1.58 17.8 1.64 17.82 1.65 17.93 1.72 18.31 1.9 18.38 1.91 18.42 1.92 18.46 1.94 18.46 1.95 18.48 1.98 18.94 2.2 18.98 2.2 19 2.2 19.05 2.23 19.1 2.26 19.15 2.3 19.2 2.32 19.21 2.32 19.22 2.32 19.32 2.36 19.42 2.41 19.53 2.46 19.64 2.51 19.68 2.52 19.71 2.54 19.75 2.56 19.78 2.57 19.84 2.61 20.42 2.9 20.48 2.91 20.51 2.92 20.57 2.95 20.6 2.97 20.63 3 20.7 3.03 20.75 3.05 20.8 3.07 20.89 3.11 20.96 3.14 21.03 3.17 21.12 3.21 21.15 3.22 21.18 3.24 21.23 3.26 21.25 3.27 21.27 3.29 21.39 3.35 21.51 3.4 21.89 3.58 22.36 3.8 22.4 3.83 22.51 3.9 22.96 4.1 23 4.1 23.03 4.1 23.07 4.12 23.11 4.15 23.14 4.18 23.18 4.2 23.19 4.2 23.2 4.2 23.3 4.24 23.41 4.3 24.06 4.61 24.55 4.85 24.94 5.02 25.03 5.07 25.25 5.17 25.42 5.26 26.1 5.58 26.37 5.71 26.46 5.75 26.52 5.78 26.63 5.83 26.71 5.86 26.79 5.9 26.95 5.98 27.06 6.03 27.18 6.08 27.28 6.12 27.28 6.12 27.29 6.12 27.34 6.15 27.39 6.19 27.44 6.22 27.52 6.26 27.57 6.28 27.62 6.29 27.69 6.33 27.72 6.35 27.76 6.38 27.81 6.4 27.84 6.4 27.87 6.4 27.92 6.42 27.95 6.45 28.03 6.5 28.44 6.7 28.48 6.7 28.5 6.7 28.55 6.73 28.6 6.76 28.65 6.8 28.7 6.82 28.72 6.82 28.75 6.82 28.87 6.88 29.56 7.22 30 7.42 30.18 7.51 30.65 7.72 30.68 7.74 30.82 7.81 30.95 7.87 31.08 7.94 31.2 8 31.22 8 31.24 8 31.28 8.02 31.3 8.03 31.32 8.05 31.46 8.12 31.6 8.18 31.74 8.25 31.88 8.31 31.9 8.33 31.92 8.34 31.98 8.37 32.02 8.39 32.07 8.42 32.19 8.47 32.29 8.52 32.38 8.56 32.48 8.6 32.5 8.6 32.52 8.6 32.57 8.62 32.6 8.65 32.63 8.68 32.67 8.7 32.68 8.7 32.71 8.7 33.36 9.01 33.42 9.05 33.45 9.06 33.49 9.09 33.52 9.1 33.58 9.12 33.8 9.23 34.11 9.38 34.25 9.44 34.48 9.55 34.65 9.62 34.68 9.64 34.73 9.66 34.75 9.67 34.77 9.69 34.89 9.75 35.01 9.8 35.14 9.86 35.41 10 35.63 10.1 35.84 10.21 36.04 10.3 36.08 10.31 36.14 10.33 36.24 10.38 36.9 10.7 37.3 10.89 37.52 11 37.83 11.13 37.9 11.17 37.98 11.2 38 11.2 38.02 11.2 38.05 11.21 38.06 11.22 38.1 11.26 38.59 11.5 38.63 11.5 38.65 11.5 38.69 11.52 38.72 11.55 38.76 11.58 38.8 11.6 38.81 11.6 38.82 11.6 38.98 11.67 39.16 11.76 39.75 12.05 39.86 12.1 39.9 12.1 39.92 12.1 39.97 12.12 40 12.15 40.03 12.18 40.07 12.2 40.08 12.2 40.1 12.2 40.7 12.49 40.85 12.58 40.87 12.59 40.96 12.63 41.06 12.67 41.15 12.72 41.29 12.78 41.38 12.82 41.47 12.86 41.64 12.94 41.78 13 41.91 13.06 42.15 13.17 42.32 13.26 43.11 13.63 43.27 13.71 43.36 13.75 43.41 13.78 43.47 13.8 43.49 13.8 43.51 13.8 43.56 13.82 43.6 13.84 43.63 13.87 43.74 13.92 43.82 13.96 43.91 14 44.01 14.05 44.04 14.07 44.06 14.08 44.11 14.1 44.13 14.1 44.15 14.1 44.19 14.12 44.23 14.14 44.28 14.18 44.55 14.31 44.8 14.42 44.83 14.44 44.88 14.46 44.9 14.47 44.92 14.49 45.04 14.54 45.16 14.6 45.29 14.66 45.41 14.72 45.43 14.73 45.53 14.78 45.58 14.8 46.04 15.01 46.15 15.06 46.37 15.17 46.54 15.25 46.84 15.39 47.2 15.57 47.39 15.65 47.51 15.71 48.26 16.07 49.03 16.43 49.22 16.52 49.39 16.6 49.4 16.6 49.41 16.6 49.6 16.69 49.81 16.8 50.03 16.91 50.22 17 50.23 17 50.24 17 50.29 17.02 50.32 17.04 50.36 17.07 50.49 17.14 50.62 17.2 50.76 17.26 51 17.37 51.17 17.45 51.34 17.53 51.49 17.6 51.5 17.6 51.51 17.6 51.63 17.66 51.76 17.72 51.9 17.79 52.1 17.88 52.21 17.93 52.32 17.99 52.43 18.04 52.45 18.05 52.47 18.07 52.55 18.11 52.62 18.14 52.7 18.17 52.8 18.22 52.85 18.25 52.91 18.28 52.96 18.3 52.99 18.3 53.01 18.3 53.07 18.33 53.12 18.36 53.17 18.4 53.22 18.42 53.23 18.42 53.24 18.42 53.33 18.46 53.43 18.51 53.53 18.56 53.64 18.61 53.68 18.62 53.71 18.64 53.75 18.66 53.78 18.68 53.8 18.69 53.91 18.75 54.04 18.8 54.16 18.86 54.28 18.91 54.3 18.93 54.32 18.94 54.38 18.97 54.42 18.99 54.47 19.01 54.59 19.07 54.69 19.11 54.78 19.16 54.94 19.23 55.04 19.28 55.13 19.32 55.32 19.41 55.46 19.48 55.6 19.54 55.74 19.61 55.78 19.62 55.81 19.64 55.85 19.66 55.88 19.67 55.9 19.69 56 19.74 56.11 19.79 56.22 19.84 56.46 19.95 56.64 20.04 56.82 20.13 56.99 20.2 57 20.2 57.02 20.2 57.07 20.22 57.1 20.25 57.13 20.28 57.17 20.3 57.18 20.3 57.2 20.3 57.41 20.4 57.95 20.66 58.12 20.74 58.32 20.83 58.4 20.87 58.63 20.97 58.87 21.09 59.3 21.3 59.53 21.41 59.87 21.57 60.06 21.66 60.25 21.76 60.43 21.84 60.45 21.85 60.47 21.87 60.5 21.88 60.52 21.89 60.74 21.98 61.86 22.5 61.95 22.55 61.97 22.57 62.05 22.6 62.12 22.64 62.2 22.67 62.3 22.72 62.35 22.75 62.41 22.78 62.47 22.8 62.5 22.8 62.52 22.8 62.55 22.81 62.56 22.82 62.58 22.85 63.64 23.37 63.74 23.39 63.77 23.4 63.81 23.42 63.83 23.44 63.84 23.46 63.9 23.49 63.95 23.5 64 23.52 64.07 23.55 64.1 23.58 64.13 23.6 64.22 23.64 64.29 23.66 64.36 23.69 64.44 23.73 64.48 23.75 64.51 23.78 64.57 23.8 64.62 23.81 64.66 23.82 64.71 23.84 64.73 23.86 64.74 23.88 64.77 23.9 64.78 23.9 64.8 23.9 65.19 24.08 65.29 24.13 65.42 24.21 65.81 24.4 65.84 24.4 65.85 24.4 65.96 24.45 66.07 24.5 66.87 24.89 67.24 25.07 67.38 25.12 67.41 25.14 67.54 25.21 67.68 25.28 67.81 25.34 67.92 25.4 67.94 25.4 67.95 25.4 68.05 25.44 68.16 25.5 68.27 25.56 68.38 25.6 68.4 25.6 68.42 25.6 68.47 25.62 68.5 25.65 68.53 25.68 68.58 25.7 68.6 25.7 68.62 25.7 68.71 25.74 68.81 25.8 68.9 25.86 68.99 25.9 68.99 25.9 69 25.9 69.19 25.99 69.42 26.1 69.64 26.21 69.85 26.31 69.89 26.31 69.92 26.32 69.96 26.35 69.98 26.36 69.99 26.38 70.02 26.4 70.04 26.4 70.05 26.4 70.16 26.44 70.27 26.5 70.38 26.56 70.49 26.6 70.51 26.6 70.53 26.6 70.57 26.62 70.6 26.65 70.64 26.67 70.69 26.7 70.72 26.71 70.76 26.72 70.83 26.76 70.88 26.79 70.94 26.83 71.03 26.88 71.08 26.9 71.3 27 72.08 27.5 72.43 27.76 73.28 28.39 74.27 29.37 74.78 30.09 74.87 30.21 75.36 30.94 75.42 31.04 75.63 31.39 75.89 31.88 76.05 32.24 76.23 32.64 76.3 32.81 76.3 32.83 76.3 32.84 76.32 32.89 76.34 32.93 76.38 33.03 76.58 33.62 76.64 33.88 76.77 34.33 76.9 34.88 76.9 34.96 76.9 34.99 76.92 35.14 76.95 35.29 76.98 35.44 77.01 35.66 77.02 35.79 77.03 35.91 77.06 36.01 77.07 36.02 77.11 36.03 77.11 38.27 77.07 38.28 77.06 38.29 77.03 38.39 77.02 38.53 76.98 38.94 76.85 39.65 76.75 40.04 76.72 40.13 76.69 40.26 76.68 40.31 76.66 40.37 76.63 40.49 76.6 40.59 76.57 40.68 76.53 40.82 76.51 40.89 76.49 40.96 76.46 41.05 76.44 41.09 76.42 41.14 76.4 41.19 76.4 41.2 76.4 41.22 76.38 41.28 76.35 41.34 76.32 41.39 76.3 41.45 76.3 41.47 76.3 41.48 76.27 41.56 76.24 41.64 76.2 41.72 76.16 41.81 76.15 41.84 75.9 42.44 75.49 43.2 75.13 43.72 75.08 43.79 75.02 43.88 75 43.91 74.87 44.12 74.32 44.8 74.01 45.14 73.32 45.89 72.32 46.7 71.49 47.18 71.41 47.22 71.31 47.28 71.27 47.31 71 47.47 70.54 47.7 69.94 47.99 69.8 48.05 69.6 48.15 69.49 48.2 69.14 48.36 68.77 48.54 68.54 48.65 68.26 48.78 67.86 48.97 67.59 49.1 67.26 49.26 66.88 49.44 66.64 49.55 66.35 49.69 65.66 50.01 65.24 50.21 65.11 50.27 64.91 50.37 64.78 50.43 64.06 50.77 63.67 50.95 63.34 51.11 62.98 51.29 62.65 51.44 62.41 51.55 62.19 51.65 61.85 51.81 61.46 52 60.9 52.26 60.72 52.35 60.51 52.45 60.3 52.55 60.02 52.68 59.55 52.9 59.28 53.03 59.01 53.16 58.67 53.32 58.52 53.39 58.28 53.51 58.13 53.58 57.98 53.65 57.77 53.75 57.66 53.8 57.54 53.86 57.36 53.94 57.24 54 56.68 54.27 56.49 54.35 56.29 54.45 56.16 54.51 55.94 54.61 55.8 54.68 55.22 54.96 55.14 55 54.44 55.33 54.29 55.4 54.06 55.5 53.93 55.57 53.8 55.63 53.59 55.73 53.46 55.79 53.32 55.85 53.12 55.95 53.01 56 52.73 56.14 52.33 56.33 52.06 56.45 51.82 56.56 51.44 56.75 51.11 56.9 50.84 57.03 50.44 57.22 50.16 57.35 50.04 57.41 49.82 57.51 49.68 57.58 49.53 57.65 49.32 57.75 49.21 57.8 49.1 57.85 48.89 57.95 48.75 58.02 48.61 58.09 48.39 58.19 48.26 58.25 48.14 58.31 47.92 58.41 47.78 58.48 47.63 58.55 47.42 58.65 47.31 58.7 47.2 58.75 47.01 58.85 46.88 58.91 46.74 58.97 46.52 59.07 46.39 59.14 46.25 59.2 46.02 59.31 45.88 59.38 45.73 59.45 45.52 59.55 45.41 59.6 45.29 59.66 45.11 59.74 44.99 59.8 44.79 59.9 44.49 60.04 43.99 60.28 43.84 60.35 43.62 60.45 43.51 60.5 43.39 60.56 43.21 60.64 43.09 60.7 42.98 60.75 42.77 60.85 42.62 60.92 42.48 60.99 42.25 61.1 42.11 61.16 41.98 61.23 41.76 61.33 41.62 61.39 41.49 61.45 41.3 61.55 41.19 61.6 41.08 61.65 40.87 61.75 40.72 61.82 40.58 61.89 40.35 62 40.21 62.06 40.08 62.13 39.86 62.23 39.72 62.29 39.59 62.35 39.4 62.45 39.29 62.5 39.18 62.55 38.97 62.65 38.82 62.72 38.68 62.79 38.46 62.89 38.34 62.95 38.06 63.08 37.66 63.27 37.39 63.4 37.06 63.55 36.68 63.74 36.44 63.85 36.17 63.97 35.77 64.16 35.49 64.3 35.38 64.35 35.18 64.45 35.04 64.51 34.91 64.57 34.7 64.67 34.57 64.73 34.44 64.8 34.21 64.9 34.06 64.97 33.91 65.05 33.7 65.15 33.59 65.2 33.48 65.25 33.28 65.35 33.15 65.41 33.02 65.47 32.81 65.57 32.68 65.63 32.54 65.69 32.31 65.8 32.16 65.87 32.01 65.95 31.8 66.05 31.69 66.1 31.58 66.15 31.38 66.25 31.24 66.31 31.11 66.37 30.9 66.47 30.77 66.54 30.64 66.6 30.44 66.69 30.31 66.75 30.06 66.87 29.67 67.05 29.32 67.22 29.09 67.33 28.99 67.38 28.47 67.62 28.1 67.8 27.7 67.99 27.46 68.1 27.34 68.16 27.16 68.24 27.04 68.3 26.48 68.57 26.29 68.65 26.09 68.75 25.96 68.81 25.74 68.91 25.6 68.98 25.02 69.26 24.93 69.3 24.24 69.63 24.09 69.7 23.86 69.8 23.74 69.86 23.61 69.92 23.4 70.02 23.26 70.09 23.12 70.15 22.92 70.25 22.81 70.3 22.7 70.35 22.49 70.45 22.34 70.53 22.19 70.6 21.96 70.7 21.83 70.77 21.7 70.83 21.49 70.93 21.36 70.99 21.22 71.05 21.02 71.15 20.91 71.2 20.63 71.34 20.23 71.53 19.96 71.65 19.73 71.76 19.36 71.94 19.01 72.1 18.81 72.2 18.57 72.31 18.09 72.54 17.95 72.6 17.72 72.71 17.58 72.78 16.64 73.22 16.49 73.29 16.09 73.45 16.02 73.48 15.93 73.52 15.88 73.54 15.79 73.58 15.21 73.77 14.95 73.85 14.45 74 13.57 74.18 13.08 74.22 12.94 74.24 12.83 74.26 12.83 74.27 12.82 74.31 10.68 74.31 10.67 74.27\\p0",
    -- white text
    "{\\c&HFFFFFF&\\p1}m 14.51 45.79 b 14.5 45.78 14.5 43.68 14.51 41.12 l 14.52 36.49 14.58 36.18 b 14.68 35.7 14.72 35.58 14.89 35.1 14.98 34.84 15.25 34.34 15.45 34.05 16.1 33.1 16.92 32.43 18.01 31.96 18.19 31.89 18.79 31.7 18.85 31.7 18.88 31.7 18.99 31.68 19.1 31.65 19.22 31.63 19.5 31.59 19.74 31.58 20.78 31.51 21.72 31.7 22.67 32.17 23.86 32.77 24.91 33.92 25.35 35.13 25.51 35.56 25.6 35.86 25.6 35.94 25.6 35.96 25.62 36.05 25.64 36.12 25.76 36.56 25.75 37.76 25.64 38.27 25.53 38.74 25.49 38.88 25.33 39.27 24.81 40.64 23.59 41.86 22.2 42.41 21.71 42.6 21.3 42.7 20.73 42.78 20.41 42.82 19.49 42.79 19.21 42.74 18.76 42.65 18.29 42.52 18.11 42.44 18.07 42.42 18.02 42.4 18.01 42.4 17.97 42.4 17.53 42.19 17.36 42.09 17.31 42.05 17.25 42.02 17.22 42.01 17.16 41.98 16.9 41.8 16.73 41.67 16.6 41.58 16.56 41.56 16.53 41.58 16.51 41.6 16.5 41.9 16.5 43.24 16.5 44.94 16.5 44.98 16.39 44.98 16.38 44.98 16.27 45.02 16.14 45.09 15.93 45.19 15.66 45.32 15.08 45.59 14.94 45.65 14.78 45.73 14.72 45.76 14.59 45.83 14.53 45.84 14.51 45.79 m 40.61 42.79 b 40.53 42.78 40.23 42.72 40 42.68 39.8 42.64 39.54 42.56 39.34 42.49 39.24 42.45 39.14 42.42 39.11 42.41 39.05 42.39 38.55 42.15 38.39 42.06 37.67 41.65 36.94 40.96 36.49 40.26 36.44 40.18 36.4 40.12 36.4 40.11 36.4 40.1 36.38 40.07 36.36 40.05 36.31 39.99 36 39.37 36 39.32 36 39.3 35.99 39.27 35.98 39.26 35.96 39.25 35.93 39.18 35.91 39.11 35.89 39.03 35.86 38.95 35.85 38.94 35.84 38.92 35.82 38.88 35.82 38.84 35.81 38.8 35.78 38.68 35.75 38.58 35.51 37.62 35.52 36.59 35.8 35.61 35.84 35.46 35.88 35.34 36.01 35.01 36.02 34.97 36.1 34.8 36.19 34.64 36.77 33.49 37.73 32.57 38.91 32.04 39.14 31.94 39.34 31.87 39.5 31.82 39.55 31.81 39.66 31.78 39.75 31.75 40.44 31.55 41.6 31.51 42.25 31.66 42.34 31.68 42.46 31.71 42.52 31.72 42.73 31.77 43.01 31.85 43.04 31.88 43.05 31.89 43.08 31.9 43.11 31.9 43.23 31.9 44.07 32.33 44.38 32.55 44.45 32.61 44.55 32.68 44.6 32.71 44.75 32.81 45.15 33.18 45.35 33.4 45.53 33.6 45.9 34.08 45.9 34.11 45.9 34.12 45.94 34.18 45.98 34.24 46.08 34.39 46.4 35.02 46.4 35.08 46.4 35.1 46.41 35.13 46.42 35.14 46.43 35.14 46.48 35.26 46.52 35.41 46.57 35.55 46.62 35.71 46.64 35.78 46.66 35.84 46.69 35.96 46.7 36.05 46.71 36.14 46.74 36.26 46.76 36.31 46.79 36.44 46.81 42.72 46.78 42.76 46.76 42.78 44.85 42.79 44.83 42.76 44.82 42.75 44.81 42.48 44.8 42.16 44.79 41.76 44.78 41.56 44.76 41.56 44.74 41.55 44.67 41.6 44.6 41.66 44.46 41.76 44.15 41.98 44.08 42.01 44.05 42.02 43.99 42.06 43.94 42.09 43.88 42.12 43.76 42.18 43.68 42.22 43.59 42.27 43.48 42.32 43.45 42.34 43.24 42.45 42.62 42.63 42.09 42.74 41.87 42.78 40.83 42.81 40.61 42.79 m 31.96 42.74 b 31.56 42.67 31.44 42.65 31.32 42.62 31.15 42.58 30.82 42.48 30.72 42.44 30.16 42.22 29.84 42.04 29.35 41.71 28.88 41.38 28.23 40.69 27.91 40.18 27.8 40 27.65 39.74 27.62 39.68 27.61 39.64 27.55 39.52 27.5 39.41 27.44 39.29 27.4 39.19 27.4 39.17 27.4 39.16 27.38 39.11 27.36 39.07 27.32 38.98 27.26 38.79 27.21 38.57 27.2 38.49 27.17 38.39 27.15 38.35 27.13 38.27 27.12 38.18 27.05 37.64 27.03 37.51 27.03 35.8 27.03 32.96 l 27.04 28.49 27.1 28.49 b 27.16 28.5 27.3 28.56 28.01 28.9 28.27 29.02 28.59 29.17 28.81 29.27 28.9 29.31 28.98 29.36 28.99 29.38 29 29.4 29.02 31.23 29.03 33.45 29.04 36.58 29.05 37.53 29.07 37.68 29.11 37.91 29.22 38.31 29.26 38.4 29.28 38.43 29.3 38.48 29.3 38.49 29.3 38.54 29.49 38.91 29.55 39 29.58 39.04 29.6 39.08 29.6 39.09 29.6 39.09 29.65 39.17 29.71 39.24 30.05 39.72 30.52 40.12 30.99 40.36 31.2 40.47 31.52 40.6 31.58 40.6 31.6 40.6 31.66 40.62 31.71 40.64 31.85 40.69 32.42 40.78 32.62 40.77 32.84 40.77 33.46 40.69 33.59 40.64 33.64 40.62 33.71 40.6 33.73 40.6 33.75 40.6 33.82 40.58 33.88 40.55 33.94 40.53 34.05 40.48 34.12 40.45 34.2 40.41 34.33 40.35 34.42 40.29 34.51 40.24 34.59 40.2 34.59 40.2 34.6 40.2 34.63 40.18 34.67 40.15 34.77 40.08 34.8 40.1 34.98 40.37 35.2 40.69 35.58 41.13 35.84 41.35 35.95 41.46 36.05 41.56 36.05 41.58 36.05 41.62 35.88 41.77 35.68 41.89 35.48 42.01 35.24 42.15 35.18 42.18 35.14 42.19 35.1 42.21 35.08 42.22 35.05 42.24 35.02 42.26 35 42.27 34.76 42.37 34.67 42.4 34.55 42.44 34.3 42.54 34.14 42.58 34.04 42.6 33.98 42.61 33.86 42.64 33.78 42.66 33.29 42.77 32.45 42.81 31.96 42.74 m 56.88 42.74 b 56.83 42.69 56.84 28.54 56.89 28.5 56.93 28.47 56.92 28.47 57.41 28.7 58.45 29.19 58.73 29.32 58.75 29.32 58.76 29.32 58.79 29.35 58.81 29.37 58.85 29.42 58.85 29.55 58.85 31.08 58.85 32.94 58.84 32.87 59.01 32.75 59.15 32.64 59.61 32.33 59.68 32.3 60.35 31.94 60.69 31.82 61.38 31.66 61.92 31.54 63.01 31.54 63.57 31.66 63.92 31.74 64.39 31.88 64.56 31.96 64.6 31.98 64.71 32.03 64.8 32.06 64.88 32.1 65.03 32.17 65.12 32.23 65.22 32.28 65.3 32.32 65.31 32.32 65.33 32.32 65.8 32.65 65.98 32.78 66.43 33.14 67.14 33.95 67.3 34.31 67.32 34.34 67.35 34.41 67.39 34.46 67.56 34.76 67.69 35.06 67.82 35.49 67.95 35.89 67.98 35.99 68 36.18 68.01 36.28 68.04 36.42 68.05 36.49 68.09 36.62 68.12 42.6 68.09 42.72 l 68.07 42.78 67.1 42.78 b 66.24 42.78 66.13 42.77 66.11 42.74 66.11 42.71 66.1 41.41 66.1 39.84 66.1 37.1 66.1 36.98 66.05 36.68 65.95 36.08 65.78 35.64 65.45 35.14 65.31 34.91 64.74 34.35 64.51 34.19 64.33 34.07 63.8 33.8 63.75 33.8 63.74 33.8 63.67 33.78 63.6 33.75 63.27 33.62 63.04 33.59 62.48 33.59 61.92 33.59 61.53 33.65 61.31 33.76 61.27 33.78 61.22 33.8 61.21 33.8 61.15 33.8 60.7 34.02 60.55 34.12 59.65 34.7 59.07 35.59 58.89 36.65 58.88 36.73 58.86 38.13 58.85 39.78 l 58.84 42.76 57.87 42.77 b 57.15 42.77 56.9 42.77 56.88 42.74 m 9.08 42.68 b 8.68 42.63 8.22 42.53 8.01 42.44 7.97 42.42 7.92 42.4 7.9 42.4 7.88 42.4 7.81 42.37 7.5 42.21 7.11 42.01 6.91 41.87 6.54 41.5 6.35 41.31 6.2 41.14 6.2 41.12 6.2 41.11 6.16 41.04 6.11 40.98 6.07 40.91 6 40.78 5.95 40.69 5.91 40.59 5.86 40.5 5.85 40.48 5.74 40.26 5.61 39.49 5.67 39.41 5.7 39.38 5.82 39.38 6.65 39.38 7.71 39.38 7.66 39.37 7.69 39.56 7.75 39.93 8.14 40.32 8.65 40.52 9.23 40.75 9.85 40.71 10.48 40.41 10.9 40.2 11.23 39.74 11.15 39.47 11.1 39.31 10.82 39.03 10.56 38.89 10.29 38.74 9.81 38.47 9.56 38.35 9.3 38.21 8.84 37.98 8.39 37.74 8.18 37.63 7.91 37.49 7.79 37.42 7.1 37.07 6.81 36.87 6.43 36.49 6.18 36.23 5.96 35.93 5.85 35.68 5.82 35.6 5.78 35.5 5.76 35.45 5.61 35.11 5.62 34.35 5.78 33.88 5.83 33.7 6.01 33.34 6.06 33.27 6.08 33.25 6.1 33.22 6.1 33.21 6.1 33.17 6.34 32.89 6.57 32.68 7.2 32.06 8.1 31.67 9.02 31.6 11.05 31.44 12.83 32.64 13.13 34.38 13.19 34.71 13.2 34.82 13.16 34.86 13.12 34.91 11.27 34.92 11.2 34.88 11.19 34.87 11.16 34.79 11.14 34.7 11.03 34.23 10.57 33.84 9.92 33.66 9.02 33.41 7.76 33.95 7.68 34.62 7.66 34.79 7.68 34.85 7.8 35 7.89 35.11 8.24 35.4 8.29 35.4 8.3 35.4 8.39 35.45 8.5 35.51 8.67 35.61 8.93 35.75 9.64 36.11 10.26 36.43 10.71 36.67 11.2 36.93 12.16 37.45 12.68 37.93 12.96 38.55 12.99 38.64 13.04 38.73 13.05 38.76 13.11 38.86 13.16 39.19 13.17 39.49 13.2 40.63 12.54 41.62 11.35 42.23 11.15 42.33 10.99 42.4 10.96 42.4 10.95 42.4 10.88 42.42 10.81 42.45 10.34 42.63 9.56 42.73 9.08 42.68 m 51.21 42.63 b 51.1 42.61 50.95 42.58 50.88 42.56 50.8 42.54 50.7 42.51 50.66 42.51 50.55 42.49 50.07 42.29 49.86 42.17 48.85 41.63 48.16 40.65 48.11 39.68 48.1 39.52 48.1 39.44 48.12 39.41 48.15 39.38 48.29 39.38 49.1 39.38 50.1 39.38 50.1 39.38 50.1 39.5 50.1 39.68 50.31 40.02 50.53 40.2 50.67 40.32 50.96 40.5 51.01 40.5 51.02 40.5 51.07 40.52 51.11 40.54 51.24 40.6 51.62 40.68 51.85 40.68 52.58 40.68 53.31 40.3 53.54 39.81 53.7 39.45 53.51 39.17 52.85 38.8 52.72 38.73 52.6 38.66 52.58 38.65 52.55 38.64 52.46 38.59 52.36 38.54 52.15 38.43 51.72 38.21 51.21 37.94 50.83 37.74 50.36 37.49 50.09 37.35 49.25 36.92 48.78 36.51 48.38 35.86 48.36 35.84 48.34 35.78 48.32 35.75 48.31 35.72 48.28 35.66 48.27 35.64 48.12 35.35 48.04 34.54 48.14 34.18 48.16 34.09 48.19 33.97 48.2 33.91 48.23 33.82 48.26 33.73 48.39 33.48 48.54 33.16 48.93 32.68 49.2 32.49 49.26 32.45 49.35 32.38 49.41 32.33 49.57 32.21 50.15 31.9 50.21 31.9 50.22 31.9 50.26 31.88 50.31 31.86 50.42 31.81 50.81 31.7 50.86 31.7 50.88 31.7 50.97 31.68 51.05 31.66 51.16 31.62 51.29 31.61 51.82 31.61 52.49 31.61 52.59 31.62 52.99 31.75 53.08 31.78 53.16 31.8 53.18 31.8 53.2 31.8 53.25 31.82 53.31 31.85 53.36 31.88 53.41 31.9 53.43 31.9 53.47 31.9 53.87 32.1 54.07 32.23 54.74 32.64 55.28 33.33 55.48 34.01 55.59 34.4 55.64 34.79 55.58 34.86 55.55 34.89 55.41 34.9 54.6 34.9 53.57 34.9 53.62 34.91 53.59 34.74 53.52 34.29 53.04 33.85 52.38 33.66 51.42 33.38 50.1 33.99 50.1 34.7 50.1 34.92 50.34 35.19 50.74 35.41 51.03 35.58 51.8 35.98 52.64 36.41 53.21 36.7 53.8 37.02 53.85 37.06 53.87 37.08 53.92 37.1 53.95 37.12 54.02 37.15 54.05 37.17 54.28 37.32 54.67 37.58 55.18 38.1 55.3 38.38 55.31 38.41 55.34 38.45 55.35 38.48 55.59 38.87 55.67 39.65 55.53 40.2 55.3 41.07 54.7 41.77 53.77 42.22 53.68 42.27 53.59 42.31 53.56 42.33 53.51 42.36 53.29 42.44 53.15 42.48 53.1 42.49 53.01 42.52 52.95 42.54 52.53 42.67 51.66 42.71 51.21 42.63 m 20.69 40.75 b 21.87 40.53 22.82 39.84 23.32 38.84 23.38 38.72 23.44 38.59 23.45 38.57 23.64 38.19 23.76 37.35 23.7 36.79 23.53 35.12 22.18 33.77 20.51 33.6 19.95 33.54 19.1 33.66 18.73 33.85 18.71 33.86 18.62 33.9 18.54 33.94 17.92 34.23 17.38 34.74 16.96 35.44 16.8 35.69 16.65 36.14 16.56 36.59 16.28 38.06 17.07 39.66 18.43 40.38 19.14 40.74 19.98 40.88 20.69 40.75 m 41.82 40.74 b 42.53 40.6 43.05 40.35 43.57 39.9 43.75 39.74 44.2 39.24 44.2 39.19 44.2 39.18 44.22 39.15 44.24 39.13 44.28 39.08 44.5 38.65 44.55 38.52 45.09 37.1 44.76 35.61 43.68 34.57 43.2 34.1 42.69 33.83 41.94 33.65 41.44 33.52 40.51 33.58 40.07 33.75 40.01 33.78 39.94 33.8 39.93 33.8 39.9 33.8 39.49 33.99 39.36 34.07 38.62 34.5 38.04 35.22 37.77 36.05 37.52 36.79 37.52 37.59 37.77 38.32 38.05 39.18 38.71 39.96 39.51 40.38 40.24 40.76 41.06 40.89 41.82 40.74\\p0"
}
-- called by mpv on every frame
function tick()
    if (not state.enabled) then return end

    if (state.idle) then

        -- render idle message
        msg.trace("idle message")
        local icon_x, icon_y = 320 - 26, 140
        local line_prefix = ("{\\rDefault\\an7\\1a&H00&\\bord0\\shad0\\pos(%f,%f)\\fscx100\\fscy100}"):format(icon_x, icon_y)
        
		local ass = assdraw.ass_new()
        -- mpv logo
        for i, line in ipairs(logo_lines) do
            ass:new_event()
            ass:an(7)
            ass:append(line_prefix .. line)
        end

        ass:new_event()
        ass:pos(320, icon_y+65)
        ass:an(8)
        ass:append(user_opts.logotext)
        set_osd(640, 360, ass.text)

        if state.showhide_enabled then
            mp.disable_key_bindings("showhide")
            mp.disable_key_bindings("showhide_wc")
            state.showhide_enabled = false
        end


    elseif (state.fullscreen and user_opts.showfullscreen)
        or (not state.fullscreen and user_opts.showwindowed) then

        -- render the OSC
        render()
    else
        -- Flush OSD
        set_osd(osc_param.playresy, osc_param.playresy, "")
    end

    state.tick_last_time = mp.get_time()

    if state.anitype ~= nil then
        request_tick()
    end
end

function do_enable_keybindings()
    if state.enabled then
        if not state.showhide_enabled then
            mp.enable_key_bindings("showhide", "allow-vo-dragging+allow-hide-cursor")
            mp.enable_key_bindings("showhide_wc", "allow-vo-dragging+allow-hide-cursor")
        end
        state.showhide_enabled = true
    end
end

function enable_osc(enable)
    state.enabled = enable
    if enable then
        do_enable_keybindings()
    else
        hide_osc() -- acts immediately when state.enabled == false
        if state.showhide_enabled then
            mp.disable_key_bindings("showhide")
            mp.disable_key_bindings("showhide_wc")
        end
        state.showhide_enabled = false
    end
end


validate_user_opts()

mp.register_event("shutdown", shutdown)
mp.register_event("start-file", request_init)
mp.observe_property("track-list", nil, request_init)
mp.observe_property("playlist", nil, request_init)
mp.observe_property("chapter-list", "native", function(_, list)
    list = list or {}  -- safety, shouldn't return nil
    table.sort(list, function(a, b) return a.time < b.time end)
    state.chapter_list = list
    request_init()
end)

mp.register_script_message("osc-message", show_message)
mp.register_script_message("osc-chapterlist", function(dur)
    show_message(get_chapterlist(), dur)
end)
mp.register_script_message("osc-playlist", function(dur)
    show_message(get_playlist(), dur)
end)
mp.register_script_message("osc-tracklist", function(dur)
    local msg = {}
    for k,v in pairs(nicetypes) do
        table.insert(msg, get_tracklist(k))
    end
    show_message(table.concat(msg, '\n\n'), dur)
end)

mp.observe_property("fullscreen", "bool",
    function(name, val)
        state.fullscreen = val
        request_init_resize()
    end
)
mp.observe_property("border", "bool",
    function(name, val)
        state.border = val
        request_init_resize()
    end
)
mp.observe_property("window-maximized", "bool",
    function(name, val)
        state.maximized = val
        request_init_resize()
    end
)
mp.observe_property("idle-active", "bool",
    function(name, val)
        state.idle = val
        request_tick()
    end
)
mp.observe_property("pause", "bool", pause_state)
mp.observe_property("demuxer-cache-state", "native", cache_state)
mp.observe_property("vo-configured", "bool", function(name, val)
    request_tick()
end)
mp.observe_property("playback-time", "number", function(name, val)
    request_tick()
end)
mp.observe_property("volume", "number", function(name, val)
    request_tick()
end)
mp.observe_property("osd-dimensions", "native", function(name, val)
    -- (we could use the value instead of re-querying it all the time, but then
    --  we might have to worry about property update ordering)
    request_init_resize()
end)

-- mouse show/hide bindings
mp.set_key_bindings({
    {"mouse_move",              function(e) process_event("mouse_move", nil) end},
    {"mouse_leave",             mouse_leave},
}, "showhide", "force")
mp.set_key_bindings({
    {"mouse_move",              function(e) process_event("mouse_move", nil) end},
    {"mouse_leave",             mouse_leave},
}, "showhide_wc", "force")
do_enable_keybindings()

--mouse input bindings
mp.set_key_bindings({
    {"mbtn_left",           function(e) process_event("mbtn_left", "up") end,
                            function(e) process_event("mbtn_left", "down")  end},
    {"shift+mbtn_left",     function(e) process_event("shift+mbtn_left", "up") end,
                            function(e) process_event("shift+mbtn_left", "down")  end},
    {"mbtn_right",          function(e) process_event("mbtn_right", "up") end,
                            function(e) process_event("mbtn_right", "down")  end},
    -- alias to shift_mbtn_left for single-handed mouse use
    {"mbtn_mid",            function(e) process_event("shift+mbtn_left", "up") end,
                            function(e) process_event("shift+mbtn_left", "down")  end},
    {"wheel_up",            function(e) process_event("wheel_up", "press") end},
    {"wheel_down",          function(e) process_event("wheel_down", "press") end},
    {"mbtn_left_dbl",       "ignore"},
    {"shift+mbtn_left_dbl", "ignore"},
    {"mbtn_right_dbl",      "ignore"},
}, "input", "force")
mp.enable_key_bindings("input")

mp.set_key_bindings({
    {"mbtn_left",           function(e) process_event("mbtn_left", "up") end,
                            function(e) process_event("mbtn_left", "down")  end},
}, "window-controls", "force")
mp.enable_key_bindings("window-controls")

function get_hidetimeout()
    if user_opts.visibility == "always" then
        return -1 -- disable autohide
    end
    return user_opts.hidetimeout
end

function always_on(val)
    if state.enabled then
        if val then
            show_osc()
        else
            hide_osc()
        end
    end
end

-- mode can be auto/always/never/cycle
-- the modes only affect internal variables and not stored on its own.
function visibility_mode(mode, no_osd)
    if mode == "cycle" then
        if not state.enabled then
            mode = "auto"
        elseif user_opts.visibility ~= "always" then
            mode = "always"
        else
            mode = "never"
        end
    end

    if mode == "auto" then
        always_on(false)
        enable_osc(true)
    elseif mode == "always" then
        enable_osc(true)
        always_on(true)
    elseif mode == "never" then
        enable_osc(false)
    else
        msg.warn("Ignoring unknown visibility mode '" .. mode .. "'")
        return
    end

    user_opts.visibility = mode

    if not no_osd and tonumber(mp.get_property("osd-level")) >= 1 then
        mp.osd_message("OSC visibility: " .. mode)
    end

    -- Reset the input state on a mode change. The input state will be
    -- recalcuated on the next render cycle, except in 'never' mode where it
    -- will just stay disabled.
    mp.disable_key_bindings("input")
    mp.disable_key_bindings("window-controls")
    state.input_enabled = false

    update_margins()
    request_tick()
end

visibility_mode(user_opts.visibility, true)
mp.register_script_message("osc-visibility", visibility_mode)
mp.add_key_binding(nil, "visibility", function() visibility_mode("cycle") end)

mp.register_script_message("thumbfast-info", function(json)
    local data = utils.parse_json(json)
    if type(data) ~= "table" or not data.width or not data.height then
        msg.error("thumbfast-info: received json didn't produce a table with thumbnail information")
    else
        thumbfast = data
    end
end)

set_virt_mouse_area(0, 0, 0, 0, "input")
set_virt_mouse_area(0, 0, 0, 0, "window-controls")