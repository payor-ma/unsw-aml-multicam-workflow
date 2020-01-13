/**
  Matthew Payor
  Multicam SL2515v and M2412 Post Processor for Fusion360
  UNSW Built Environment, Advanced Manufacturing Lab

  Modified from a post developed by Autodesk for generic AXYZ router tables
  https://cam.autodesk.com/posts/download.php?name=axyz
*/

description = "For AML SL2515v and M2412";
vendor = "Multicam Australia";
vendorUrl = "https://www.making.unsw.edu.au/our-network/our-machines/flat-bed-cnc-routers/";
legal = "by Matthew Payor, modified from a generic Autodesk post";

longDescription = "Post for UNSW Built Environment, Advanced Manufacturing Lab, Multicam SL2515v and M2412 router tables";

extension = "nc";
programNameIsInteger = false;
setCodePage("ascii");

capabilities = CAPABILITY_MILLING;


// Tolerance set low to reduce instructions since controllers are slow

tolerance = spatial(0.05, MM);

// Default G2/3 usage settings
minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.1, MM);
maximumCircularRadius = spatial(3000, MM);
minimumCircularSweep = toRad(0.5);
maximumCircularSweep = toRad(90);
allowHelicalMoves = false; // disallow helical moves - TEST
//allowSpiralMoves = false; // disallow spiral interpolation - TEST
allowedCircularPlanes = (1 << PLANE_XY); // allow XY plane only

// PUSHED OUT OF PROPERTIES
/**
writeMachine: true; // write machine
writeTools: true; // writes the tools
preloadTool: true; // preloads next tool on tool change if any
showSequenceNumbers: true; // show sequence numbers
sequenceNumberStart: 10; // first sequence number
sequenceNumberIncrement: 10; // increment for sequence numbers
useM6: true; // specifies to use M6 for tool changes

writeMachine: {title:"Write machine", description:"Output the machine settings in the header of the code.", group:0, type:"boolean"},
writeTools: {title:"Write tool list", description:"Output a tool list in the header of the code.", group:0, type:"boolean"},
preloadTool: {title:"Preload tool", description:"Preloads the next tool at a tool change (if any).", type:"boolean"},
showSequenceNumbers: {title:"Use sequence numbers", description:"Use sequence numbers for each block of outputted code.", group:1, type:"boolean"},
sequenceNumberStart: {title:"Start sequence number", description:"The number at which to start the sequence numbers.", group:1, type:"integer"},
sequenceNumberIncrement: {title:"Sequence number increment", description:"The amount by which the sequence number is incremented by in each block.", group:1, type:"integer"},
separateWordsWithSpace: {title:"Separate words with space", description:"Adds spaces between words if 'yes' is selected.", type:"boolean"},
useM6: {title:"Use M6", description:"Specifies if M6 should be used for tool changes.", type:"boolean"}
*/


// user-defined properties
properties = {
//  beep: false,
  vacuumUse: "default",
  useDusty: true,
  optionalStop: "operation" // optional stop default to true

};

// TODO: IMPLEMENT OPTIONS

// user-defined property definitions
propertyDefinitions = {
//  beep: {title:"Beep", description:"Boop.",type:"boolean"},
  
  vacuumUse: {title:"Auto vacuum table policy", description:"Options for automatic vacuum table behaviour", type:"enum",
    values:[
      {title:"Do not use", id:"off"},
      {title:"On for duration of job", id:"default"},
      {title:"Sustain after job completion", id:"sustain"}]
  },
  useDusty: {title:"Use dust extraction", description:"Runs the dust extraction for the duration of a program", type:"boolean"},
  optionalStop: {title:"Insert optional stops", description:"Inserts optional stops into the gcode based on option choice.", type: "enum",
    values:[
      {title:"None", id:"none"},
      {title:"Between operations", id:"operation"},
      {title:"Before toolchange", id:"toolChange"}]
  }
};

var numberOfToolSlots = 9999;

var gFormat = createFormat({prefix:"G", decimals:0});
var mFormat = createFormat({prefix:"M", decimals:0});

var xyzFormat = createFormat({decimals:(unit == MM ? 2 : 3)});
var feedFormat = createFormat({decimals:(unit == MM ? 0 : 1)});
var toolFormat = createFormat({decimals:0});
var rpmFormat = createFormat({decimals:0});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-1000
var taperFormat = createFormat({decimals:1, scale:DEG});

var xOutput = createVariable({prefix:"X"}, xyzFormat);
var yOutput = createVariable({prefix:"Y"}, xyzFormat);
var zOutput = createVariable({onchange:function () {retracted = false;}, prefix:"Z"}, xyzFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);
var sOutput = createVariable({prefix:"M3 S", force:true}, rpmFormat);

// circular output
var iOutput = createVariable({prefix:"I"}, xyzFormat);
var jOutput = createVariable({prefix:"J"}, xyzFormat);

var gMotionModal = createModal({}, gFormat); // modal group 1 // G0-G3, ...
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21 or G70-71
var gCycleModal = createModal({}, gFormat); // modal group 9 // G81, ...

// collected state
//var sequenceNumber;
var retracted = false; // specifies that the tool has been retracted to the safe plane

/**
  Writes the specified block.
*/
function writeBlock() {
  if (!formatWords(arguments)) {
    return;
  }
  if (false){//properties.showSequenceNumbers) {
    writeWords2("N" + sequenceNumber, arguments);
    sequenceNumber += properties.sequenceNumberIncrement;
  } else {
    writeWords(arguments);
  }
}

function formatComment(text) {
  return "(" + String(text).replace(/[()]/g, "") + ")";
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln(formatComment(text));
}


function onOpen() {
  //if (!properties.separateWordsWithSpace) {
  //  setWordSeparator("");
  //}

  //sequenceNumber = properties.sequenceNumberStart;
  writeln("%");

  if (programName) {
    var programId;
    try {
      programId = getAsInt(programName);
    } catch(e) {
      error(localize("Program name must be a number."));
    }
    if (!((programId >= 1) && (programId <= 9999))) {
      error(localize("Program number is out of range."));
      return;
    }
    var oFormat = createFormat({width:4, zeropad:true, decimals:0});
    writeln(":O" + oFormat.format(programId));
  } else {
    error(localize("Program name has not been specified."));
    return;
  }
  
  if (programComment) {
    writeComment(programComment);
  }

  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (vendor || model || description) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }

/**
  // Tool length warning functions
  if (dustBootWarning) {

  }

  if (toolClearanceWarning) {

  }
*/

  

  // GLOBAL PARAM STUFF
//  value = getGlobalParameter()
//'job-description', string
//'stock', '((0, 0, -5), (300, 200, 0))')
//'stock-lower-x', 0
//'stock-lower-y', 0
//'stock-lower-z', -5
//'stock-upper-x', 300
//'stock-upper-y', 200
//'stock-upper-z', 0
//'part-lower-x', 0
//'part-lower-y', 0
//'part-lower-z', -5
//'part-upper-x', 300
//'part-upper-y', 200
//'part-upper-z', 0

  // Tool overload warning function
  if (true) { // set to true to check for duplicate tool numbers w/different cutter geometry
    // check for duplicate tool number
    for (var i = 0; i < getNumberOfSections(); ++i) {
      var sectioni = getSection(i);
      var tooli = sectioni.getTool();
      for (var j = i + 1; j < getNumberOfSections(); ++j) {
        var sectionj = getSection(j);
        var toolj = sectionj.getTool();
        if (tooli.number == toolj.number) {
          if (xyzFormat.areDifferent(tooli.diameter, toolj.diameter) ||
              xyzFormat.areDifferent(tooli.cornerRadius, toolj.cornerRadius) ||
              (tooli.numberOfFlutes != toolj.numberOfFlutes)) {
            error(subst(localize("Using the same tool number for different cutter geometry for operation '%1' and'%2'."),
              sectioni.hasParameter("operation-comment") ?
              sectioni.getParameter("operation-comment") : ("#" + (i + 1)),
              sectionj.hasParameter("operation-comment") ?
              sectionj.getParameter("operation-comment") : ("#" + (j + 1))
            ));
            return;
          }
        }
      }
    }
  }

  // dump tool information
  // WRITETOOLS
  if (true) {
    var zRanges = {};
    if (is3D()) {
      var numberOfSections = getNumberOfSections();
      for (var i = 0; i < numberOfSections; ++i) {
        var section = getSection(i);
        var zRange = section.getGlobalZRange();
        var tool = section.getTool();
        if (zRanges[tool.number]) {
          zRanges[tool.number].expandToRange(zRange);
        } else {
          zRanges[tool.number] = zRange;
        }
      }
    }

    var tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var comment = "T" + toolFormat.format(tool.number) + "  " +
          "D=" + xyzFormat.format(tool.diameter) + " " +
          localize("CR") + "=" + xyzFormat.format(tool.cornerRadius);
        if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
          comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
        }
        if (zRanges[tool.number]) {
          comment += " - " + localize("ZMIN") + "=" + xyzFormat.format(zRanges[tool.number].getMinimum());
        }
        comment += " - " + getToolTypeName(tool.type);
        writeComment(comment);
      }
    }
  }

  // Turn vacuum on
  if (properties.vacuumUse != "off") {
    writeComment("(Turn vacuum on)")
    writeBlock(mFormat.format(808));
  }

  // Turn dusty on
  if (properties.useDusty) {
    writeComment("(Turn dusty on)")
    writeBlock(mFormat.format(810));
  }
  
  // absolute coordinates and feed per min
  writeBlock(gAbsIncModal.format(90));
  
  switch (unit) {
  case IN:
    writeBlock(gUnitModal.format(20));
    break;
  case MM:
    writeBlock(gUnitModal.format(21));
    break;
  }
}

function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

function isProbeOperation() {
  return hasParameter("operation-strategy") && (getParameter("operation-strategy") == "probe");
}

function onSection() {
  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);

  if (!isFirstSection() && (properties.optionalStop=="operation") ) {
      onCommand(COMMAND_OPTIONAL_STOP);
  }

  retracted = false;
  var newWorkPlane = isFirstSection() ||
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis()) ||
    (currentSection.isOptimizedForMachine() && getPreviousSection().isOptimizedForMachine() &&
      Vector.diff(getPreviousSection().getFinalToolAxisABC(), currentSection.getInitialToolAxisABC()).length > 1e-4) ||
    (!machineConfiguration.isMultiAxisConfiguration() && currentSection.isMultiAxis()) ||
    (!getPreviousSection().isMultiAxis() && currentSection.isMultiAxis() ||
      getPreviousSection().isMultiAxis() && !currentSection.isMultiAxis()); // force newWorkPlane between indexing and simultaneous operations
  if (insertToolCall || newWorkPlane) {
    
    // stop spindle before retract during tool change
    // if (insertToolCall && !isFirstSection()) {
    //   onCommand(COMMAND_STOP_SPINDLE);
    // }

    // retract to safe plane
    writeRetract(Z);
    zOutput.reset();
  }
  
  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }

  if (insertToolCall) {
    
    setCoolant(COOLANT_OFF);
  
    if (!isFirstSection() && (properties.optionalStop=="toolChange") ) {
      onCommand(COMMAND_OPTIONAL_STOP);
    }

    if (tool.number > numberOfToolSlots) {
      warning(localize("Tool number exceeds maximum value."));
    }

    //properties.useM6, mFormat.format(6)),"T" + toolFormat.format(tool.number));
    writeBlock(conditional(true, mFormat.format(6)),"T" + toolFormat.format(tool.number));
    if (tool.comment) {
      writeComment(tool.comment);
    }
    var showToolZMin = false;
    if (showToolZMin) {
      if (is3D()) {
        var numberOfSections = getNumberOfSections();
        var zRange = currentSection.getGlobalZRange();
        var number = tool.number;
        for (var i = currentSection.getId() + 1; i < numberOfSections; ++i) {
          var section = getSection(i);
          if (section.getTool().number != number) {
            break;
          }
          zRange.expandToRange(section.getGlobalZRange());
        }
        writeComment(localize("ZMIN") + "=" + zRange.getMinimum());
      }
    }

    /*
    if (properties.preloadTool) {
      var nextTool = getNextTool(tool.number);
      if (nextTool) {
        writeBlock("T" + toolFormat.format(nextTool.number));
      } else {
        // preload first tool
        var section = getSection(0);
        var firstToolNumber = section.getTool().number;
        if (tool.number != firstToolNumber) {
          writeBlock("T" + toolFormat.format(firstToolNumber));
        }
      }
    }
    */
  }
  
  if (insertToolCall ||
      isFirstSection() ||
      (rpmFormat.areDifferent(spindleSpeed, sOutput.getCurrent()))) {
    if (spindleSpeed < 1) {
      error(localize("Spindle speed out of range."));
      return;
    }
    // Enforcing max spindle speed of 18000
    if (spindleSpeed > 18000) {
      warning(localize("Spindle speed exceeds maximum value."));
    }
    writeBlock(sOutput.format(spindleSpeed));
  }

  forceXYZ();

  { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  // set coolant after we have positioned at Z
  setCoolant(tool.coolant);

  forceAny();

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted && !insertToolCall) {
    if (getCurrentPosition().z < initialPosition.z) {
      writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
    }
  }

  if (insertToolCall || retracted) {
    if (!machineConfiguration.isHeadConfiguration()) {
      writeBlock(
        gAbsIncModal.format(90),
        gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y)
      );
      writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
    } else {
      writeBlock(
        gAbsIncModal.format(90),
        gMotionModal.format(0),
        xOutput.format(initialPosition.x),
        yOutput.format(initialPosition.y),
        zOutput.format(initialPosition.z)
      );
    }
  } else {
    writeBlock(
      gAbsIncModal.format(90),
      gMotionModal.format(0),
      xOutput.format(initialPosition.x),
      yOutput.format(initialPosition.y)
    );
  }
}

function onDwell(seconds) {
  if (seconds > 99999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  seconds = clamp(0.001, seconds, 99999.999);
  writeBlock(gFormat.format(4), "P" + secFormat.format(seconds));
}

function onSpindleSpeed(spindleSpeed) {
  writeBlock(sOutput.format(spindleSpeed));
}

function onCycle() {
}

function getCommonCycle(x, y, z, r) {
  forceXYZ();
  return [xOutput.format(x), yOutput.format(y),
    zOutput.format(z),
    "R" + xyzFormat.format(r)];
}

function onCyclePoint(x, y, z) {
    expandCyclePoint(x, y, z);
    return;
  if (!isSameDirection(getRotation().forward, new Vector(0, 0, 1))) {
    expandCyclePoint(x, y, z);
    return;
  }
  if (isFirstCyclePoint()) {
    repositionToCycleClearance(cycle, x, y, z);
    expandCyclePoint(x, y, z);
    return;
    var F = cycle.feedrate;
    var P = !cycle.dwell ? 0 : clamp(0.001, cycle.dwell, 99999.999); // in seconds

    switch (cycleType) {
    case "drilling":
      writeBlock(
        gAbsIncModal.format(90), gCycleModal.format(81),
        getCommonCycle(x, y, z, cycle.retract),
        feedOutput.format(F)
      );
      break;
    case "counter-boring":
      if (P > 0) {
        writeBlock(
          gAbsIncModal.format(90), gCycleModal.format(82),
          getCommonCycle(x, y, z, cycle.retract),
          "P" + secFormat.format(P),
          feedOutput.format(F)
        );
      } else {
        writeBlock(
          gAbsIncModal.format(90), gCycleModal.format(81),
          getCommonCycle(x, y, z, cycle.retract),
          feedOutput.format(F)
        );
      }
      break;
    case "deep-drilling":
      writeBlock(
        gAbsIncModal.format(90), gCycleModal.format(83),
        getCommonCycle(x, y, z, cycle.retract),
        "Q" + xyzFormat.format(cycle.incrementalDepth),
        "P" + secFormat.format(P),
        feedOutput.format(F)
      );
      break;
    case "reaming":
      writeBlock(
        gAbsIncModal.format(90), gCycleModal.format(85),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + secFormat.format(P),
        feedOutput.format(F)
      );
      break;
    case "boring":
      writeBlock(
        gAbsIncModal.format(90), gCycleModal.format(85),
        getCommonCycle(x, y, z, cycle.retract),
        "P" + secFormat.format(P),
        feedOutput.format(F)
      );
      break;
    default:
      expandCyclePoint(x, y, z);
    }
  } else {
    if (cycleExpanded) {
      expandCyclePoint(x, y, z);
    } else {
      var _x = xOutput.format(x);
      var _y = yOutput.format(y);
      if (!_x && !_y) {
        xOutput.reset(); // at least one axis is required
        _x = xOutput.format(x);
      }
      writeBlock(_x, _y);
    }
  }
}

function onCycleEnd() {
  if (!cycleExpanded) {
    writeBlock(gCycleModal.format(80));
    zOutput.reset();
  }
}

function onRadiusCompensation() {
  if (radiusCompensation != RADIUS_COMPENSATION_OFF) {
    error(localize("Radius compensation is not supported."));
  }
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    writeBlock(gMotionModal.format(0), x, y, z);
    feedOutput.reset();
  }
}

function onLinear(_x, _y, _z, feed) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);
  if (x || y || z) {
    writeBlock(gMotionModal.format(1), x, y, z, f);
  } else if (f) {
    if (getNextRecord().isMotion()) { // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (isHelical()) {
    linearize(tolerance);
    return;
  }

  switch (getCircularPlane()) {
  case PLANE_XY:
    writeBlock(gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), zOutput.format(z), iOutput.format(cx), jOutput.format(cy), feedOutput.format(feed));
    break;
  default:
    linearize(tolerance);
  }
}

var currentCoolantMode = undefined;
var coolantOff = undefined;

function setCoolant(coolant) {
  if (!properties.outputCoolantCommands) {
    return undefined;
  }
  var coolantCodes = getCoolantCodes(coolant);
  if (Array.isArray(coolantCodes)) {
    for (var c in coolantCodes) {
      writeBlock(coolantCodes[c]);
    }
    return undefined;
  }
  return coolantCodes;
}

function getCoolantCodes(coolant) {
  if (!coolants) {
    error(localize("Coolants have not been defined."));
  }
  if (!coolantOff) { // use the default coolant off command when an 'off' value is not specified for the previous coolant mode
    coolantOff = coolants.off;
  }

  if (isProbeOperation()) { // avoid coolant output for probing
    coolant = COOLANT_OFF;
  }

  if (coolant == currentCoolantMode) {
    return undefined; // coolant is already active
  }

  var multipleCoolantBlocks = new Array(); // create a formatted array to be passed into the outputted line
  if ((coolant != COOLANT_OFF) && (currentCoolantMode != COOLANT_OFF)) {
    multipleCoolantBlocks.push(mFormat.format(coolantOff));
  }

  var m;
  if (coolant == COOLANT_OFF) {
    m = coolantOff;
    coolantOff = coolants.off;
  }

  switch (coolant) {
  case COOLANT_FLOOD:
    if (!coolants.flood) {
      break;
    }
    m = coolants.flood.on;
    coolantOff = coolants.flood.off;
    break;
  case COOLANT_THROUGH_TOOL:
    if (!coolants.throughTool) {
      break;
    }
    m = coolants.throughTool.on;
    coolantOff = coolants.throughTool.off;
    break;
  case COOLANT_AIR:
    if (!coolants.air) {
      break;
    }
    m = coolants.air.on;
    coolantOff = coolants.air.off;
    break;
  case COOLANT_AIR_THROUGH_TOOL:
    if (!coolants.airThroughTool) {
      break;
    }
    m = coolants.airThroughTool.on;
    coolantOff = coolants.airThroughTool.off;
    break;
  case COOLANT_FLOOD_MIST:
    if (!coolants.floodMist) {
      break;
    }
    m = coolants.floodMist.on;
    coolantOff = coolants.floodMist.off;
    break;
  case COOLANT_MIST:
    if (!coolants.mist) {
      break;
    }
    m = coolants.mist.on;
    coolantOff = coolants.mist.off;
    break;
  case COOLANT_SUCTION:
    if (!coolants.suction) {
      break;
    }
    m = coolants.suction.on;
    coolantOff = coolants.suction.off;
    break;
  case COOLANT_FLOOD_THROUGH_TOOL:
    if (!coolants.floodThroughTool) {
      break;
    }
    m = coolants.floodThroughTool.on;
    coolantOff = coolants.floodThroughTool.off;
    break;
  }
  
  if (!m) {
    onUnsupportedCoolant(coolant);
    m = 9;
  }

  if (m) {
    if (Array.isArray(m)) {
      for (var i in m) {
        multipleCoolantBlocks.push(mFormat.format(m[i]));
      }
    } else {
      multipleCoolantBlocks.push(mFormat.format(m));
    }
    currentCoolantMode = coolant;
    return multipleCoolantBlocks; // return the single formatted coolant value
  }
  return undefined;
}

var mapCommand = {
  COMMAND_STOP:0,
  COMMAND_OPTIONAL_STOP:1,
  // COMMAND_STOP_SPINDLE:5, // do not use since we cannot enable spindle again
  COMMAND_LOAD_TOOL:6
};

function onCommand(command) {
  switch (command) {
  case COMMAND_START_SPINDLE:
    // onCommand(tool.clockwise ? COMMAND_SPINDLE_CLOCKWISE : COMMAND_SPINDLE_COUNTERCLOCKWISE);
    return;
  }

  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  forceAny();
}

/** Output block to do safe retract and/or move to home position. */
function writeRetract() {
  if (arguments.length == 0) {
    error(localize("No axis specified for writeRetract()."));
    return;
  }
  var words = []; // store all retracted axes in an array
  for (var i = 0; i < arguments.length; ++i) {
    let instances = 0; // checks for duplicate retract calls
    for (var j = 0; j < arguments.length; ++j) {
      if (arguments[i] == arguments[j]) {
        ++instances;
      }
    }
    if (instances > 1) { // error if there are multiple retract calls for the same axis
      error(localize("Cannot retract the same axis twice in one line"));
      return;
    }
    switch (arguments[i]) {
    case X:
      words.push("X" + xyzFormat.format(machineConfiguration.hasHomePositionX() ? machineConfiguration.getHomePositionX() : 0));
      break;
    case Y:
      words.push("Y" + xyzFormat.format(machineConfiguration.hasHomePositionY() ? machineConfiguration.getHomePositionY() : 0));
      break;
    case Z:
      words.push("Z" + xyzFormat.format(machineConfiguration.getRetractPlane()));
      retracted = true; // specifies that the tool has been retracted to the safe plane
      break;
    default:
      error(localize("Bad axis specified for writeRetract()."));
      return;
    }
  }
  if (words.length > 0) {
    gMotionModal.reset();
    gAbsIncModal.reset(); //commenting incremental line
    // writeBlock(gFormat.format(28), gAbsIncModal.format(91), words)
    writeBlock(gAbsIncModal.format(90));
  }
  zOutput.reset();
}

function onClose() {
  setCoolant(COOLANT_OFF);
  writeRetract(Z);
  
  writeBlock(gFormat.format(28)); // return to home

  onImpliedCommand(COMMAND_END);
  onImpliedCommand(COMMAND_STOP_SPINDLE);
  
  // Turn vacuum off
  if (properties.vacuumUse == "default") {
    writeComment("(Turn vacuum off)")
    writeBlock(mFormat.format(809));
  }
  
  // Turn dusty off
  if (properties.useDusty) {
    writeComment("(Turn dusty off)")
    writeBlock(mFormat.format(811));
  }
  
  writeBlock(mFormat.format(30)); // stop program, spindle stop, coolant off
  writeln("%");
}