wait until ag8 or ag9.
wait 6.
clearScreen.

set ship:name to "Mechazilla". 
Print " Mechazilla is Operational".
until False{
    processCommCommands().
}

function processCommCommands{
	WHEN NOT SHIP:MESSAGES:EMPTY THEN{
	  SET RECEIVED TO SHIP:MESSAGES:POP.
	  SET cmd TO RECEIVED:CONTENT.

	  if(cmd="Close arms"){
		ag10 on.
        Print "Closing Arms" at(1,1).
	  }
	}
}