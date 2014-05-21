CF-SSQ
======

Coldfusion Source Server Queries

This is a library for Coldfusion for getting information about a TF2, HL2:DM, DoD:S, etc server. 

Information about what you can gather is found here: https://developer.valvesoftware.com/wiki/Server_queries

All functions have their corresponding names.


Not working
-------

- Compression of packets has not been implanted (yet)
- Support for The Ship added.
- No GoldSRC support as of yet.

Usage
-------
Load the CFC

	<cfset VARIABLES.SSQCF = createObject("component","sourcemod") />

All functions return Structs if the connection succeeded, and the data that is collected	

**Get players**
This will get all players and their scores + play times.

	<cfset VARIABLES.myPlayers = VARIABLES.SSQCF.A2S_INFO(ip="127.0.0.1",port="27015") />

Returns within a struct an array with players.

**Get server information**
This will get information about the server, the amount of players, the host name, etc.

	<cfset VARIABLES.myPlayers = VARIABLES.SSQCF.A2S_RULES(ip="127.0.0.1",port="27015") />
	
**Get server rules**
This will get all convars that are available to everyone to see

	<cfset VARIABLES.myPlayers = VARIABLES.SSQCF.A2S_RULES(ip="127.0.0.1",port="27015") />
	
Returns a struct with all the rules and their values
	
Since A2A_PING and A2S_SERVERQUERY_GETCHALLENGE are obsolete for now they haven't been added to the CFC.
	
Tested
-------
I've tested this on a Railo environment and tried to keep it compatible with CF8 and higher.


