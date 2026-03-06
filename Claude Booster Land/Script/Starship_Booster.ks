print "Starship booster landing start".

set targetLat to -0.0990775578062799.
set targetLng to -74.5573890967578.

set burnStartMargin to 650.
set burnMargin to 180.
set minThrottle to 0.38.
set maxThrottleStep to 0.05.
set safetyFactor to 1.35.

set flareAlt to 140.
set flareHardAlt to 90.
set vTargetHigh to -18.
set vTargetLow to -2.0.
set vTargetLowAlt to 15.
set kVhold to 0.012.

set kPos to 0.018.
set kVel to 0.25.
set kLat to 0.035.
set maxTilt to 0.20.

set tgoMax to 25.
set minVertFactorBurn to 0.88.
set minVertFactorHard to 0.94.

set landingBurn to false.
set lastThrottle to 0.

function clamp {
  parameter x, lo, hi.
  if x < lo { return lo. }.
  if x > hi { return hi. }.
  return x.
}.

function slew {
  parameter current, target, step.
  if target > current + step { return current + step. }.
  if target < current - step { return current - step. }.
  return target.
}.

function vscale {
  parameter vec, s.
  return vec * s.
}.

function metersPerDegLat {
  return body:radius * constant():pi / 180.
}.

function metersPerDegLon {
  parameter latDeg.
  return body:radius * constant():pi / 180 * cos(latDeg * constant():pi / 180).
}.

function timeToGround {
  parameter rAlt, vSpeed, g, aNetUp.

  set vDown to 0.
  if vSpeed < 0 { set vDown to 0 - vSpeed. }.
  if rAlt < 1 { return 0.1. }.

  if aNetUp > 0.1 {
    set A to 0.5 * aNetUp.
    set B to 0 - vDown.
    set C to rAlt.

    set disc to B*B - 4*A*C.
    if disc < 0 { set disc to 0. }.

    set t1 to ((0 - B) - sqrt(disc)) / (2*A).
    set t2 to ((0 - B) + sqrt(disc)) / (2*A).

    if t1 > 0 { return t1. }.
    if t2 > 0 { return t2. }.
    return 0.1.
  }.

  set A to 0.5 * g.
  set B to vDown.
  set C to 0 - rAlt.

  set disc to B*B - 4*A*C.
  if disc < 0 { set disc to 0. }.

  set t to ((0 - B) + sqrt(disc)) / (2*A).
  if t < 0.1 { set t to 0.1. }.
  return t.
}.

function suicideThrottle {
  parameter vSpeed, rAlt, thrustNow, m, g, margin, minT, safety, vertFactor.

  set vDown to 0.
  if vSpeed < 0 { set vDown to 0 - vSpeed. }.

  set d to rAlt - margin.
  if d < 1 { set d to 1. }.

  set aNetReq to (vDown * vDown) / (2 * d).

  set aMaxUp to (thrustNow * vertFactor) / m.
  if aMaxUp < 0.1 { return 1. }.

  set aTotalReq to (aNetReq + g) * safety.
  set tCmd to aTotalReq / aMaxUp.

  set tCmd to clamp(tCmd, 0, 1).
  if tCmd > 0 { set tCmd to clamp(tCmd, minT, 1). }.

  return tCmd.
}.

function vTargetAtAlt {
  parameter rAlt, vHigh, vLow, lowAlt, flareA.

  if rAlt >= flareA { return vHigh. }.
  if rAlt <= lowAlt { return vLow. }.

  set t to (rAlt - lowAlt) / (flareA - lowAlt).
  return vLow + (vHigh - vLow) * t.
}.

until ship:verticalspeed < 0 { wait 0.1. }.
lock throttle to 0.

until ship:status = "LANDED" {

  set rAlt to ship:bounds:bottomaltradar.
  set vSurf to ship:velocity:surface.
  set vSpeed to ship:verticalspeed.

  set thrustNow to ship:availablethrust.
  set m to ship:mass.
  set g to body:mu / (body:radius + altitude)^2.

  if thrustNow <= 0 and rAlt < 20000 {
    stage.
    wait 0.2.
    set thrustNow to ship:availablethrust.
    if thrustNow <= 0 {
      stage.
      wait 0.2.
      set thrustNow to ship:availablethrust.
    }.
  }.

  set upVec to ship:up:vector:normalized.
  set northVec to ship:north:vector:normalized.
  set eastVec to vcrs(upVec, northVec):normalized.

  set dLat to targetLat - ship:geoposition:lat.
  set dLng to targetLng - ship:geoposition:lng.

  set northErr to dLat * metersPerDegLat().
  set eastErr to dLng * metersPerDegLon(ship:geoposition:lat).

  set vUp to vscale(upVec, vSpeed).
  set vLat to vSurf - vUp.

  set vE to vdot(vLat, eastVec).
  set vN to vdot(vLat, northVec).

  set baseDir to upVec.
  if vSurf:mag > 5 {
    set baseDir to vscale(vSurf, -1):normalized.
  }.

  set tiltLimitNow to maxTilt.
  if landingBurn { set tiltLimitNow to maxTilt * 0.55. }.
  if rAlt < flareHardAlt { set tiltLimitNow to maxTilt * 0.25. }.

  set aNetUpForTgo to 0.
  if landingBurn and thrustNow > 0 {
    set aMaxUp0 to thrustNow / m.
    set maxDecel0 to aMaxUp0 - g.
    if maxDecel0 < 0.5 { set maxDecel0 to 0.5. }.
    set aNetUpForTgo to maxDecel0.
  }.

  set tgo to timeToGround(rAlt, vSpeed, g, aNetUpForTgo).
  set tgo to clamp(tgo, 0.1, tgoMax).

  set predEast to vE * tgo.
  set predNorth to vN * tgo.

  set eastErrLead to eastErr - predEast.
  set northErrLead to northErr - predNorth.

  set cmdE to eastErrLead * kPos - vE * kVel.
  set cmdN to northErrLead * kPos - vN * kVel.

  set latVec to vscale(eastVec, cmdE) + vscale(northVec, cmdN).
  set latVec to vscale(latVec, kLat).

  if latVec:mag > tiltLimitNow {
    set latVec to vscale(latVec:normalized, tiltLimitNow).
  }.

  set steerVec to baseDir + latVec.
  if steerVec:mag < 0.001 { set steerVec to upVec. }.
  set steerDir to steerVec:normalized.

  set vertFactor to vdot(steerDir, upVec).
  set vertFactor to clamp(vertFactor, 0.25, 1).

  if landingBurn {
    if vertFactor < minVertFactorBurn {
      set latVec to vscale(latVec, 0.4).
      set steerVec to baseDir + latVec.
      set steerDir to steerVec:normalized.
      set vertFactor to vdot(steerDir, upVec).
      set vertFactor to clamp(vertFactor, 0.25, 1).
    }.
  }.

  if rAlt < flareHardAlt {
    if vertFactor < minVertFactorHard {
      set latVec to vscale(latVec, 0.2).
      set steerVec to upVec + latVec.
      set steerDir to steerVec:normalized.
      set vertFactor to vdot(steerDir, upVec).
      set vertFactor to clamp(vertFactor, 0.25, 1).
    }.
  }.

  lock steering to steerDir.

  if thrustNow > 0 {

    set vDown to 0.
    if vSpeed < 0 { set vDown to 0 - vSpeed. }.

    set aMaxUp to (thrustNow * vertFactor) / m.
    set maxDecel to aMaxUp - g.
    if maxDecel < 0.5 { set maxDecel to 0.5. }.

    set stopDist to (vDown * vDown) / (2 * maxDecel).

    if (not landingBurn) and (stopDist + burnStartMargin >= rAlt) {
      set landingBurn to true.
    }.

    if (not landingBurn) and (rAlt < 5000) and (vSpeed < -30) {
      set landingBurn to true.
    }.

    if landingBurn {

      set throttleCmd to suicideThrottle(vSpeed, rAlt, thrustNow, m, g, burnMargin, minThrottle, safetyFactor, vertFactor).

      if rAlt < flareAlt {
        set vT to vTargetAtAlt(rAlt, vTargetHigh, vTargetLow, vTargetLowAlt, flareAlt).
        set hover to (m * g) / (thrustNow * vertFactor).
        set holdCmd to hover + (vT - vSpeed) * kVhold.
        set throttleCmd to clamp(holdCmd, minThrottle, 1).
      }.

      if rAlt < flareHardAlt {
        set hoverHard to (m * g) / (thrustNow * vertFactor).
        set holdHard to hoverHard + (vTargetLow - vSpeed) * (kVhold * 1.6).
        set throttleCmd to clamp(holdHard, minThrottle, 1).
      }.

      set throttleCmd to slew(lastThrottle, throttleCmd, maxThrottleStep).
      set lastThrottle to throttleCmd.
      lock throttle to throttleCmd.

    } else {
      set lastThrottle to slew(lastThrottle, 0, maxThrottleStep).
      lock throttle to lastThrottle.
    }.

  } else {
    set lastThrottle to 0.
    lock throttle to 0.
  }.

  wait 0.05.
}.

lock throttle to 0.
print "LANDED".