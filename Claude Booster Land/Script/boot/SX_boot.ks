clearscreen.
// 800 IPU: fast enough for GNC math, low enough not to freeze KSP on launch.
// 2000 was causing the game freeze on spacebar/throttle-up.
set config:ipu to 800.
switch to 0.

// Safety: if vessel is destroyed or reverted, unlock controls and die cleanly.
when (ship:status = "DEAD" or kuniverse:activevessel:name <> ship:name) then {
    unlock steering. unlock throttle.
    set ship:control:neutralize to true.
}

// set tags then run prerequesites

list processors in coreList.
local coreIterate is 0.

for core in coreList {
	for core in coreList {

		if ((core:part:name = "TE.19.F9.S1.Interstage" or 
			core:part:name = "TE.19.F9.S1.Interstage (" + ship:name + ")") and // weird bug from ksp,
			coreIterate = 0) {														// reverting from VAB,
			set core:tag to "1".													// interstage as root
			set coreIterate to coreIterate + 1.
		}
		print coreIterate.
	}

	if (core:part:name = "TE.19.FH.NoseCone" and coreIterate > 0) {
		set core:tag to (coreIterate + 1):tostring.
		set coreIterate to coreIterate + 1.
	}
}

// Auto-stage at 57km — fires once when altitude crosses 57km, stages immediately.
// This ensures consistent separation altitude every run without manual input.
// Only arms if there are stages remaining (stage:number > 0).
when (ship:altitude > 57000 and stage:number > 0) then {
    if (stage:ready) { stage. }
}

if (core:tag = "1" or core:tag = "2" or core:tag = "3") {
	// core:doEvent("Open Terminal").
	runpath("0:/SPACEX/BOOSTER").
}
else {
	// core:doEvent("Open Terminal").
	runpath("0:/SPACEX/PAYLOAD").
}

// set avd to vecDraw(ship:position, v(0,0,0), blue, "", 2.0, true).
// set avd:vecupdater to { return v(0,0,0) * 10. }.