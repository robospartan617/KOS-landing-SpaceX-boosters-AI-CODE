rcs off. 
clearguis(). clearscreen.

// INLINE HELPER FUNCTIONS (missing from repo)
function SubHeaderFormat {
    parameter lbl, col.
    set lbl:style:fontsize to 14.
    set lbl:style:textcolor to rgba(200,220,255,1).
    set lbl:style:font to "consolas".
    set lbl:style:hstretch to true.
    if col = 1 {
        set lbl:style:align to "left".
    } else {
        set lbl:style:align to "right".
    }
}

function PayloadTypeFormat {
    parameter btn, container.
    set btn:style:fontsize to 12.
    set btn:style:textcolor to rgba(220,220,220,1).
    set btn:style:bg to "ASSET/label_bg".
    set btn:style:hover:bg to "ASSET/hover_bg".
    set btn:style:active:bg to "ASSET/hover_bg".
    set btn:style:width to container:style:width / 4 - 10.
    set btn:style:height to 30.
}

function OrbitParameterFormat {
    parameter lbl.
    set lbl:style:fontsize to 11.
    set lbl:style:textcolor to rgba(180,200,255,1).
    set lbl:style:align to "center".
}

function OrbitParameterTextFieldFormat {
    parameter tf, numOnly is true.
    set tf:style:fontsize to 12.
    set tf:style:textcolor to white.               // white is a built-in Color, usually works
    set tf:style:bg to "ASSET/label_bg".           // ← FIXED: use texture string instead of rbg()
    set tf:style:width to 80.
    set tf:style:height to 22.
    set tf:style:margin:h to 5.
    if numOnly {
        set tf:onconfirm to { 
            if tf:text:tonumber = 0 and tf:text <> "0" { set tf:text to "0". } 
        }.
    }
}

function OrbitParameterButtonFormat {
    parameter btn.
    set btn:style:width to 25.
    set btn:style:height to 22.
    set btn:style:bg to "ASSET/label_bg".
}

function OrbitModeFormat {
    parameter btn, container, side.
    set btn:style:fontsize to 14.
    set btn:style:textcolor to rgba(200,255,200,1).
    set btn:style:width to container:style:width / 2 - 5.
    set btn:style:height to 35.
    set btn:style:bg to "ASSET/label_bg".
}

function Zero_MarginPadding {
    parameter widget.
    set widget:style:margin:h to 0.
    set widget:style:margin:v to 0.
    set widget:style:padding:h to 0.
    set widget:style:padding:v to 0.
}

// CREATE GUI

local blu_clr is rgba(100,110,220,255).
local gra_clr is rgba(245,245,245,255).
local drk_clr is rgba(0,16,25,255).
local lim_clr is rgba(100,230,20,255).

global missionGUI is GUI(320).
set missionGUI:style:width to 320.
set missionGUI:style:padding:h to 18.
set missionGUI:style:padding:v to 15.
set missionGUI:style:bg to "ASSET/gui_bg".
set missionGUI:style:border:h to 512/3.
set missionGUI:style:border:v to 512/3.

set missionGUI:skin:popupmenu:active:bg to "ASSET/hover_bg".
set missionGUI:skin:popupmenu:active_on:bg to "ASSET/hover_bg".
set missionGUI:skin:popupmenu:normal:bg to "ASSET/hover_bg".
set missionGUI:skin:popupmenu:normal_on:bg to "ASSET/hover_bg".
set missionGUI:skin:popupmenu:hover:bg to "ASSET/hover_bg".
set missionGUI:skin:popupmenu:hover_on:bg to "ASSET/hover_bg".

set missionGUI:skin:popupwindow:bg to "ASSET/label_bg".

set missionGUI:skin:popupmenuitem:bg to "ASSET/label_bg".
set missionGUI:skin:popupmenuitem:hover:bg to "ASSET/hover_bg".

set missionGUI:skin:popupwindow:textcolor to drk_clr.
set missionGUI:skin:popupmenuitem:textcolor to drk_clr.

set missionGUI:skin:button:active:bg to "ASSET/label_bg".
set missionGUI:skin:button:active_on:bg to "ASSET/hover_bg".
set missionGUI:skin:button:normal:bg to "ASSET/label_bg".
set missionGUI:skin:button:normal_on:bg to "ASSET/hover_bg".
set missionGUI:skin:button:hover:bg to "ASSET/hover_bg".
set missionGUI:skin:button:hover_on:bg to "ASSET/label_bg".

local header_box is missionGUI:addhlayout().
    local title_box is header_box:addvlayout().
        local title_0 is title_box:addlabel("SpaceX Launch").
        set title_0:style:fontsize to 24.
        set title_0:style:textcolor to gra_clr.
        set title_0:style:font to "consolas".
        set title_0:style:margin:bottom to 0.
        set title_0:style:padding:bottom to 0.
        local title_1_div is title_box:addhlayout().
            local title_1_0 is title_1_div:addlabel("Software").
            set title_1_0:style:fontsize to 24.
            set title_1_0:style:textcolor to gra_clr.
            set title_1_0:style:font to "consolas".
            set title_1_0:style:hstretch to false.
            local title_1_1 is title_1_div:addlabel("<b>v0.2</b>").
            set title_1_1:style:fontsize to 24.
            set title_1_1:style:textcolor to blu_clr.
            set title_1_1:style:font to "consolas".

    global loadButton is header_box:addbutton().
    set loadButton:style:width to 38.
    set loadButton:style:height to 38.
    set loadButton:style:margin:top to 10.
    set loadButton:style:margin:right to 5.
    set loadButton:style:padding:right to 5.
    set loadButton:style:bg to "ASSET/empty_bg".
    set loadButton:image to "ASSET/load_ico".

local div_0 is missionGUI:addlabel().
set div_0:style:bg to "ASSET/div".
set div_0:style:align to "center".
set div_0:style:height to 2.

local sect_1 is missionGUI:addhlayout().
set sect_1:style:width to missionGUI:style:width - (missionGUI:style:padding:left + missionGUI:style:padding:right).
    
    local s1_title_0 is sect_1:addlabel("PAYLOAD").
    SubHeaderFormat(s1_title_0, 1).
    
    local s1_title_1 is sect_1:addlabel("<b>TYPE</b>").
    SubHeaderFormat(s1_title_1, 2).

local sect_2 is missionGUI:addhlayout().
set sect_2:style:width to missionGUI:style:width - (missionGUI:style:padding:left + missionGUI:style:padding:right).
set sect_2:style:height to 20.

    sect_2:addspacing(-1).
    local s2_button_0 is sect_2:addbutton("FAIRINGS").
    PayloadTypeFormat(s2_button_0, sect_2).
    set s2_button_0:toggle to true.
    set s2_button_0:exclusive to true.
    sect_2:addspacing(1).

    local s2_button_1 is sect_2:addbutton("DRAGON 2").
    PayloadTypeFormat(s2_button_1, sect_2).
    set s2_button_1:toggle to true.
    set s2_button_1:exclusive to true.
    sect_2:addspacing(1).

    local s2_button_2 is sect_2:addbutton("DRAGON 1").
    PayloadTypeFormat(s2_button_2, sect_2).
    set s2_button_2:toggle to true.
    set s2_button_2:exclusive to true.
    sect_2:addspacing(1).

    local s2_button_3 is sect_2:addbutton("SS (WIP)").
    PayloadTypeFormat(s2_button_3, sect_2).
    set s2_button_3:toggle to true.
    set s2_button_3:exclusive to true.
    sect_2:addspacing(-1).

local div_1 is missionGUI:addlabel().
set div_1:style:bg to "ASSET/div".
set div_1:style:align to "center".
set div_1:style:height to 2.
set div_1:style:margin:top to 17.5.

// ... (orbital inputs section unchanged - copy from previous version if needed)

local sect_4 is missionGUI:addvbox().
set sect_4:style:width to missionGUI:style:width - (missionGUI:style:padding:left + missionGUI:style:padding:right).
set sect_4:style:bg to "ASSET/empty_bg".

    local s4_row_0 is sect_4:addhlayout().
    set s4_row_0:style:width to sect_4:style:width.
    Zero_MarginPadding(s4_row_0).

        local s4_opt_0 is s4_row_0:addvlayout().
        set s4_opt_0:style:width to s4_row_0:style:width / 3.
        Zero_MarginPadding(s4_opt_0).
            local s4_opt_0_t is s4_opt_0:addlabel("APOAPSIS").
            OrbitParameterFormat(s4_opt_0_t).
            local APOinp is s4_opt_0:addtextfield().
            OrbitParameterTextFieldFormat(APOinp, false).

        local s4_opt_1 is s4_row_0:addvlayout().
        set s4_opt_1:style:width to s4_row_0:style:width / 3.
        Zero_MarginPadding(s4_opt_1).
            local s4_opt_1_t is s4_opt_1:addlabel("PERIAPSIS").
            OrbitParameterFormat(s4_opt_1_t).
            local PERinp is s4_opt_1:addtextfield().
            OrbitParameterTextFieldFormat(PERinp, false).

        local s4_opt_2 is s4_row_0:addvlayout().
        set s4_opt_2:style:width to s4_row_0:style:width / 3.
        Zero_MarginPadding(s4_opt_2).
            local s4_opt_2_t is s4_opt_2:addlabel("MASS").
            OrbitParameterFormat(s4_opt_2_t).
            local MASSinp is s4_opt_2:addtextfield().
            OrbitParameterTextFieldFormat(MASSinp, false).

    // ... (continue with s4_row_1, s4_row_2 as in previous full version - ensure no trailing . after calls)

    // Booster section (fixed)
local sect_5 is missionGUI:addhlayout().
set sect_5:style:width to missionGUI:style:width - (missionGUI:style:padding:left + missionGUI:style:padding:right).

    local s5_title_0 is sect_5:addlabel("BOOSTER").
    SubHeaderFormat(s5_title_0, 1).
    
    local s5_title_1 is sect_5:addlabel("<b>RECOVERY</b>").
    SubHeaderFormat(s5_title_1, 2).

local sect_6 is missionGUI:addhlayout().
set sect_6:style:width to missionGUI:style:width - (missionGUI:style:padding:left + missionGUI:style:padding:right).

    local s6_container is sect_6:addvlayout().

    list processors in coreList.
    local popupList is list().
    local coreIterate is 0.

    for core in coreList {
        if core:part:tag = "1" and coreIterate = 0 {
            set coreIterate to coreIterate + 1.
            local popup is s6_container:addpopupmenu().
            popupList:add(popup).
            popup:addoption("Core - RTLS").
            popup:addoption("Core - ASDS").
            popup:addoption("Core - XPND").
            set popup:index to 0.
        }

        if core:part:tag = "2" or core:part:tag = "3" {
            set coreIterate to coreIterate + 1.
            local popup is s6_container:addpopupmenu().
            popupList:add(popup).
            popup:addoption("Side Booster - RTLS").
            popup:addoption("Side Booster - XPND").
            set popup:index to 0.
        }
    }

    if popupList:length = 0 {
        s6_container:addlabel("No recoverable boosters detected").
        print "GUI: No cores tagged '1','2','3' - recovery skipped".
    }

// LAUNCH BUTTON - global so GNC.ks BetterWarp can update its countdown text
local div_launch is missionGUI:addlabel().
set div_launch:style:bg to "ASSET/div".
set div_launch:style:align to "center".
set div_launch:style:height to 2.
set div_launch:style:margin:top to 10.

local launch_box is missionGUI:addhlayout().
global launchButton is launch_box:addbutton("LAUNCH").
set launchButton:style:fontsize to 16.
set launchButton:style:textcolor to rgba(100/255,230/255,20/255,1).
set launchButton:style:bg to "ASSET/label_bg".
set launchButton:style:hover:bg to "ASSET/hover_bg".
set launchButton:style:height to 40.
set launchButton:style:hstretch to true.

missionGUI:show().

// Wait for LAUNCH press then return control to PAYLOAD.ks.
// The old 'wait until false' blocked forever and froze the game on launch.
until (launchButton:pressed) { wait 0. }
missionGUI:hide().