<cfcomponent displayname="Source Server Queries and Rcon" hint="Used to get information from some types of gameservers">
	<!--- Might be good to know
	Made by: Ivo de Bruijn

	Description: This is a Source Server Queries CFC that talks to Source servers to get information.

	Contains: Multipacket Support, and OrangeBox games support for now

	TODO:
	- Make the code more flexible and re-use lots of code like building the packets
	- Add support for GoldSrc
	- Add compression support (and change to the proper checks for it)

	VERSION: 0.01 ALPHA
	 --->
	<cffunction name="init" returntype="any" output="false">
		<cfreturn THIS />
	</cffunction>
	
	<cffunction name="hexObject" returnType="struct" output="false" access="private">
		<cfargument name="myHex" type="string" required="true" />
		<cfset var LOCAL = structNew() />
		<cfset LOCAL.rc = structNew() />
		<cfset LOCAL.rc.sourceHex = ARGUMENTS.myHex />
		<cfset LOCAL.rc.myHex = ARGUMENTS.myHex />

		<cfreturn LOCAL.rc />
	</cffunction>

	<cffunction name="doRequest" returntype="struct" output="false" access="public">
		<cfargument name="ip" type="string" required="true" />
		<cfargument name="port" type="numeric" required="true" />
		<cfargument name="message" type="any" required="true" />
		<cfset var LOCAL = structNew() />
		<cfset LOCAL.rc = structNew() />
		<cfset LOCAL.rc.success = false />
		
		<!--- Alright, before we begin we need a couple of things
			Our current IP (or Localhost)
			Our target IP (or hostname converted) in a Java Object
			Our target port as Numeric value	
		--->
		
		
		<!--- Our source --->
		<cfset LOCAL.source = structNew() />
		<cfset LOCAL.source.ip = createObject("java","java.net.InetAddress").getByName(javaCast("string","10.0.2.15")) />
		<cfset LOCAL.source.port = javaCast("int",ARGUMENTS.port + 10000 + ceiling(RandRange(1,1000))) />
		
		<!--- To which server are we going to connect --->
		<cfset LOCAL.target = structNew() />
		<cfset LOCAL.target.ip = createObject("java","java.net.InetAddress").getByName(javaCast("string",ARGUMENTS.ip)) />
		<cfset LOCAL.target.port = javaCast("int",ARGUMENTS.port) />

		<!--- Create DatagramSocket + Setup a listening socket for UDP packets on this port --->
		<cfset LOCAL.mySocket = createObject("java","java.net.DatagramSocket").init(
			LOCAL.source.port)/>


		<cftry>
			<cfset LOCAL.myPacket = createObject("java","java.net.DatagramPacket").init(
				ARGUMENTS.message,
				javaCast("int",ArrayLen(ARGUMENTS.message)),
				LOCAL.target.ip,
				LOCAL.target.port
			)/>
			
			<cfset LOCAL.mySocket.send(LOCAL.myPacket) />

			<!--- Wait for response --->
			<cfset LOCAL.myResponse = createObject("java","java.net.DatagramPacket").init(charsetDecode(repeatString(" ", 1024),"utf-8"),javaCast("int",1024)) />
			<cfset LOCAL.mySocket.setSoTimeout(javaCast("int",5000)) />
			<!--- Shit we got stuff --->
			<cfset LOCAL.mySocket.receive(LOCAL.myResponse) />
			<!--- Get the data --->
			<cfset LOCAL.myData = LOCAL.myResponse.getData() />
			
			<cfset LOCAL.myHexData = binaryEncode(LOCAL.myData,'hex') />
			<cfset LOCAL.myHexObject = hexObject(LOCAL.myHexData) />

			<!--- Strip the first few FF's off			 --->
			<cfloop from="1" to="3" index="LOCAL.i">
				<cfset stripByte(myHex=LOCAL.myHexObject,signed=true) />
			</cfloop>
			
			<!--- Usually last FF, but could be FE indicating multipacket --->
			<cfset LOCAL.isMultiPacket = stripByte(myHex=LOCAL.myHexObject,signed=true) />
			<cfset LOCAL.rc.hexObject = LOCAL.myHexObject />
			<cfset LOCAL.rc.multiPacketArray = arrayNew(1) />
			<cfset LOCAL.shouldGetMore = false />
			<cfset LOCAL.useCompression = false />


			<!--- Todo: add support for multipacket with the new Hex reader			 --->
			<cfif LOCAL.isMultiPacket EQ -2>
				<cfset LOCAL.tempSortingArray = structNew() />

				<cfset LOCAL.shouldGetMore = true />
				<!--- Read out multipacket rules --->
				<cfset LOCAL.rc.multiPacketId = readLong(buffer=LOCAL.rc.dataByte) />
				<cfset LOCAL.rc.totalPackets = readByte(buffer=LOCAL.rc.dataByte) />
				<cfset LOCAL.rc.packetNumber = readByte(buffer=LOCAL.rc.dataByte) />
				<cfset LOCAL.rc.packetSize	= readShort(buffer=LOCAL.rc.dataByte) />
				<cfif LOCAL.rc.multiPacketId GT 2147483648>
					<cfset LOCAL.useCompression = true />
				</cfif>
				<!--- Read out compression stuff --->
				<cfif LOCAL.useCompression EQ true>
					<cfset LOCAL.myPacketSize =  readLong(buffer=LOCAL.myData) />
					<cfset LOCAL.myCRC32CheckSum = readLong(buffer=LOCAL.myData) />
				</cfif>
				<cfset LOCAL.tempSortingArray[LOCAL.rc.packetNumber + 1] = LOCAL.rc.dataByte />

			</cfif>
			<!--- Use compression 2147483648 --->
			<cfloop condition="LOCAL.shouldGetMore EQ true">

				<!--- Wait for response --->
				<cfset LOCAL.myResponse = createObject("java","java.net.DatagramPacket").init(charsetDecode(repeatString(" ", 1024),"utf-8"),javaCast("int",1024)) />
				<!--- Wait 5 seconds --->
				<cfset LOCAL.mySocket.setSoTimeout(javaCast("int",5000)) />
				<!--- Shit we got stuff --->
				<cfset LOCAL.mySocket.receive(LOCAL.myResponse) />
				<!--- Get the data --->
				<cfset LOCAL.myDataByte = LOCAL.myResponse.getData() />
				<!--- Something weird is going on here --->
				<cfset LOCAL.myData = convertByteArrayToCFArray(byteArray=LOCAL.myDataByte,maxLength=LOCAL.myResponse.getLength()) />
				<cfset LOCAL.isMultiPacket = readByte(buffer=LOCAL.myData) />
				<!--- Rip off useless FFFFFF --->
				<cfset readByte(buffer=LOCAL.myData) />
				<cfset readByte(buffer=LOCAL.myData) />
				<cfset readByte(buffer=LOCAL.myData) />

				<cfset LOCAL.multiPacketId = readLong(buffer=LOCAL.myData) />
				<cfset LOCAL.totalPackets = readByte(buffer=LOCAL.myData) />
				<cfset LOCAL.packetNumber = readByte(buffer=LOCAL.myData) />
				<cfset LOCAL.packetSize		= readShort(buffer=LOCAL.myData) />

				<cfif IsNumeric(LOCAL.packetNumber) EQ true AND LOCAL.packetNumber GTE 0>
					<cfset LOCAL.tempSortingArray[LOCAL.packetNumber + 1] = LOCAL.myData />
				</cfif>


				<!--- Check if it's empty (32 characters) --->
				<cfif LOCAL.myResponse.getLength() LT 1024>
					<cfset LOCAL.shouldGetMore = false />
				</cfif>
			</cfloop>

			<!--- Concat all stuff --->
			<cfif LOCAL.isMultiPacket EQ -2>
				<cfset LOCAL.rc.dataByte = arrayNew(1) />

				<cfloop from="1" to="#ArrayLen(LOCAL.tempSortingArray)#" index="LOCAL.i">
					<cfset LOCAL.rc.dataByte = arrayMerge(array1=LOCAL.rc.dataByte,array2=LOCAL.tempSortingArray[LOCAL.i]) />
				</cfloop>
				<!--- wtf? --->
				<cfset LOCAL.isMultiPacket = readByte(buffer=LOCAL.rc.dataByte) />
				<cfset readByte(buffer=LOCAL.rc.dataByte) />
				<cfset readByte(buffer=LOCAL.rc.dataByte) />
				<cfset readByte(buffer=LOCAL.rc.dataByte) />
			</cfif>


			<cfset LOCAL.rc.success = true />
			<!--- Always close the socket --->

			<cfset LOCAL.mySocket.close() />

			<cfcatch>
				<!--- Close socket --->
				<cfdump var="#LOCAL#" />
				<cfdump var="#CFCATCH#" />
				<cfset LOCAL.mySocket.close() />
				<!--- Just incase --->
				<cfabort />
			</cfcatch>

		</cftry>
		
		
		<cfreturn LOCAL.rc />
	</cffunction>

	<cffunction name="A2S_PLAYER" returntype="struct" output="false" access="public">
		<cfargument name="ip" type="string" required="true" />
		<cfargument name="port" type="numeric" required="true" />

		<!--- First get us a challange number --->
		<cfset var LOCAL = structNew() />
		<cfset LOCAL.rc = structNew() />
		<cfset LOCAL.rc.connected = false />
		<cfset LOCAL.rc.players = arrayNew(1) />

		<cfset LOCAL.myChallengeNumber = getChallengeNumber(ip=ARGUMENTS.ip,port=ARGUMENTS.port,startHex="55") />

		<!--- Get players --->
		<cfif LOCAL.myChallengeNumber GT 0 >


			<cfset LOCAL.challangeAsHex = FormatBaseN(LOCAL.myChallengeNumber,16) />
			<cfdump var="#LOCAL#"/><cfabort/>			
			<cfset LOCAL.message = "FFFFFFFF55" />			
<!---
			<cfset LOCAL.myBinMessage = binaryDecode(LOCAL.myMessage, 'hex') />
			<cfset LOCAL.myContents = doRequest(ip=ARGUMENTS.ip,port=ARGUMENTS.port,message=LOCAL.myBinMessage) />
--->

			
			
			<!--- Challange Header Byte (0x55)--->
			<cfset LOCAL.myHeaderByte = convertHexToByte(myHex="55") />
			<cfset LOCAL.myEmptyByte = convertHexToByte(myHex="FF") />

			<!--- Concat all bytes --->
			<cfset LOCAL.myByteBuffer = createObject("java","java.nio.ByteBuffer") />
			<!--- We need FF FF FF FF HEADERBYTE MESSAGEBYTES TERMINATOR --->
			<cfset LOCAL.myByteLength = 9 />
			<cfset LOCAL.myByteBuffContents = LOCAL.myByteBuffer.Allocate(LOCAL.myByteLength) />

			<!--- FF --->
			<cfloop from="1" to="4" index="LOCAL.i">
				<cfset LOCAL.myByteBuffContents.Put(
					LOCAL.myEmptyByte,
					javaCast("int",0),
					javaCast("int",1)
				)/>
			</cfloop>

			<!--- My Challenge Number --->
			<cfset LOCAL.myByteBuffContents.put(LOCAL.myHeaderByte)/>
			<!--- My Challenge Number --->
			<cfset LOCAL.myByteBuffContents.putInt(javaCast("long",LOCAL.myChallengeNumber))/>

			<cfset LOCAL.myByteContentsArray = LOCAL.myByteBuffContents.array() />
			<cfset LOCAL.myContents = doRequest(ip=ARGUMENTS.ip,port=ARGUMENTS.port,message=LOCAL.myByteContentsArray) />

			<cfif LOCAL.myContents.success EQ true>
				<cfset LOCAL.rc.connected = true />
				<cfset LOCAL.myData =LOCAL.myContents.dataByte />
				<!--- Strip off useless bytes --->
				<cfset LOCAL.myHeader = Chr(readByte(buffer=LOCAL.myData)) />

				<cfif LOCAL.myHeader EQ "D">


					<cfset LOCAL.rc.PlayerAmount = readByte(buffer=LOCAL.myData) />

					<cfloop from="1" to="#LOCAL.rc.PlayerAmount#" index="LOCAL.i">
						<cfset LOCAL.playerStruct = structNew() />
						<cfset LOCAL.playerStruct['index'] = readByte(buffer=LOCAL.myData)/>
						<cfset LOCAL.playerStruct['name'] = readString(buffer=LOCAL.myData)/>

						<cfset LOCAL.playerStruct['score'] = readShort(buffer=LOCAL.myData)/>
						<cfset LOCAL.playerStruct['tryFloat'] = arrayNew(1) />
						<cfset readByte(buffer=LOCAL.myData)/>
						<cfset readByte(buffer=LOCAL.myData)/>
 						<cfset LOCAL.playerStruct['duration'] = readFloat(buffer=LOCAL.myData)/>

						<!--- Player didn't connect yet ignore it --->
						<cfif Len(Trim(LOCAL.playerStruct['name'])) GT 0 >
							<cfset arrayAppend(LOCAL.rc.players,LOCAL.playerStruct) />
						</cfif>
					</cfloop>
				</cfif>
			</cfif>
		</cfif>

		<cfreturn LOCAL.rc />
	</cffunction>

	<cffunction name="getChallengeNumber" returntype="numeric" output="false" access="public">
		<cfargument name="ip" type="string" required="true" />
		<cfargument name="port" type="numeric" required="true" />
		<cfargument name="startHex" type="string" required="true" />

		<cfset var LOCAL = structNew() />
		<cfset LOCAL.rc = 0 />
		
		<!--- Total message, 4xFF startHex 4xFF		 --->
		<cfset LOCAL.myMessage = "FFFFFFFF" & ARGUMENTS.startHex & "FFFFFFFF" />

		<cfset LOCAL.myBinMessage = binaryDecode(LOCAL.myMessage, 'hex') />
		<cfset LOCAL.myContents = doRequest(ip=ARGUMENTS.ip,port=ARGUMENTS.port,message=LOCAL.myBinMessage) />
		
		<!--- Strip off useless bytes --->
		<cfset LOCAL.myHeader = stripByte(myHex=LOCAL.myContents.hexObject,type="char") />


		<!--- We can get ourselfs a challange number --->
		<cfif LOCAL.myContents.success EQ true AND LOCAL.myHeader EQ "A">
			<cfset LOCAL.rc =  stripLong(myHex=LOCAL.myContents.hexObject) />
		</cfif>
	

		<cfreturn LOCAL.rc />

	</cffunction>


	<cffunction name="A2S_RULES" returntype="struct" output="false" access="public">
		<cfargument name="ip" type="string" required="true" />
		<cfargument name="port" type="numeric" required="true" />

		<!--- First get us a challange number --->
		<cfset var LOCAL = structNew() />
		<cfset LOCAL.rc = structNew() />
		<cfset LOCAL.rc.connected = false />

		<cfset LOCAL.myChallengeNumber = getChallengeNumber(ip=ARGUMENTS.ip,port=ARGUMENTS.port,startHex="56") />

		<!--- Get players --->
		<cfif LOCAL.myChallengeNumber GT 0 >
			<!--- Challange Header Byte (0x55)--->
			<cfset LOCAL.myHeaderByte = convertHexToByte(myHex="56") />
			<cfset LOCAL.myEmptyByte = convertHexToByte(myHex="FF") />

			<!--- Concat all bytes --->
			<cfset LOCAL.myByteBuffer = createObject("java","java.nio.ByteBuffer") />
			<!--- We need FF FF FF FF HEADERBYTE MESSAGEBYTES TERMINATOR --->
			<cfset LOCAL.myByteLength = 9 />
			<cfset LOCAL.myByteBuffContents = LOCAL.myByteBuffer.Allocate(LOCAL.myByteLength) />

			<!--- FF --->
			<cfloop from="1" to="4" index="LOCAL.i">
				<cfset LOCAL.myByteBuffContents.Put(
					LOCAL.myEmptyByte,
					javaCast("int",0),
					javaCast("int",1)
				)/>
			</cfloop>

			<!--- My Challenge Number --->
			<cfset LOCAL.myByteBuffContents.put(LOCAL.myHeaderByte)/>
			<!--- My Challenge Number --->
			<cfset LOCAL.myByteBuffContents.putInt(javaCast("long",LOCAL.myChallengeNumber))/>

			<cfset LOCAL.myByteContentsArray = LOCAL.myByteBuffContents.array() />

			<cfset LOCAL.myContents = doRequest(ip=ARGUMENTS.ip,port=ARGUMENTS.port,message=LOCAL.myByteContentsArray) />
			<cfif LOCAL.myContents.success EQ true>
				<cfset LOCAL.rc.connected = true />
				<cfset LOCAL.myData = LOCAL.myContents.dataByte />
				<cfset LOCAL.myHeader = Chr(readByte(buffer=LOCAL.myData)) />
				<cfset LOCAL.rc.amountOfRules = readShort(buffer=LOCAL.myData) />

				<cfset LOCAL.rc.rules = structNew() />

				<cfif LOCAL.myHeader EQ "E">
					<cfset LOCAL.thisHasRules = true />
					<cfset LOCAL.maxLoopCount = 500 />
					<cfset LOCAL.count = 0 />
					<cfloop from="1" to="#LOCAL.rc.amountOfRules#" index="LOCAL.i">
						<cfset LOCAL.ruleName = readString(buffer=LOCAL.myData) />
						<cfset LOCAL.ruleVariable = readString(buffer=LOCAL.myData) />
						<cfif Len(Trim(LOCAL.ruleName)) GT 0 AND Len(Trim(LOCAL.ruleVariable))>
							<cfset LOCAL.rc.rules[LOCAL.ruleName] = LOCAL.ruleVariable />
						</cfif>
					</cfloop>
					<cfset LOCAL.rc.amountOfRules = structCount(LOCAL.rc.rules)	 />
				</cfif>
			</cfif>
		</cfif>

		<cfreturn LOCAL.rc />
	</cffunction>

	<cffunction name="A2S_INFO" returntype="struct" output="false" access="public">
		<cfargument name="ip" type="string" required="true" />
		<cfargument name="port" type="numeric" required="true" />
		<cfargument name="type" type="string" required="false" default="Source Engine Query" />

		<cfset var LOCAL = structNew() />
		<cfset LOCAL.rc = structNew() />
		<cfset LOCAL.rc.connected = false />		
		
		<!--- Hex Message --->
		
		<!--- Start with 4 byte FF 0xFF 0xFF 0xFF 0xFF --->
		<cfset LOCAL.myMessage = "FFFFFFFF" />
		<!--- Header: Command T	--->
		<cfset LOCAL.myMessage = LOCAL.myMessage & stringToHex("T") />
		<!--- Payload: Source Engine Query		 --->
		<cfset LOCAL.myMessage = LOCAL.myMessage & stringToHex("Source Engine Query") />
		<!--- End character 00 --->
		<cfset LOCAL.myMessage = LOCAL.myMessage & "00" />
		
		<cfset LOCAL.myBinMessage = binaryDecode(LOCAL.myMessage, 'hex') />
		<cfset LOCAL.myContents = doRequest(ip=ARGUMENTS.ip,port=ARGUMENTS.port,message=LOCAL.myBinMessage) />


		<cfset LOCAL.myData = LOCAL.myContents.hexObject />


		<cfif LOCAL.myContents.success EQ TRUE>
			<cfset LOCAL.rc.connected = true />

			<!--- Strip off useless bytes --->
			<cfset LOCAL.rc.header 		= stripByte(myHex=LOCAL.myData,type="char") />
			<cfset LOCAL.rc.protocol 	= stripByte(myHex=LOCAL.myData,type="char") />
			<cfset LOCAL.rc.hostname	= stripString(myHex=LOCAL.myData) />
			<cfset LOCAL.rc.map			= stripString(myHex=LOCAL.myData) />
			<cfset LOCAL.rc.folder		= stripString(myHex=LOCAL.myData) />
			<cfset LOCAL.rc.game		= stripString(myHex=LOCAL.myData) />
			<cfset LOCAL.rc.gameid 		= stripShort(myHex=LOCAL.myData) />
			<cfset LOCAL.rc.players 	= stripByte(myHex=LOCAL.myData,type="numeric") />
			<cfset LOCAL.rc.maxPlayers 	= stripByte(myHex=LOCAL.myData,type="numeric") />
			<cfset LOCAL.rc.bots 		= stripByte(myHex=LOCAL.myData,type="numeric") />
			<cfset LOCAL.rc.servertype 	= stripByte(myHex=LOCAL.myData,type="char") />
			<cfset LOCAL.rc.environment = stripByte(myHex=LOCAL.myData,type="char") />
			<cfset LOCAL.rc.visibility 	= stripByte(myHex=LOCAL.myData,type="numeric") />
			<cfset LOCAL.rc.vac 		= stripByte(myHex=LOCAL.myData,type="numeric") />
			
			<cfset LOCAL.rc.myEDFByte 		= stripByte(myHex=LOCAL.myData,type="numeric") />
			
			
			

	
			<!--- Compare - Hex to Numeric --->
			<cfset LOCAL.my0x80 = signedToUnsigned(InputBaseN("80",16)) />
			<cfset LOCAL.my0x40 = signedToUnsigned(InputBaseN("40",16)) />
			<cfset LOCAL.my0x20 = signedToUnsigned(InputBaseN("20",16)) />
			<cfset LOCAL.my0x10 = signedToUnsigned(InputBaseN("10",16)) />
			<cfset LOCAL.my0x01 = signedToUnsigned(InputBaseN("01",16)) />


	
			<!--- Current one is Servers Game Port --->
			<cfif LOCAL.rc.myEDFByte GTE LOCAL.my0x80>
				<cfset LOCAL.rc.gameport = stripShort(buffer=LOCAL.myData)/>
			</cfif>
			<!--- What ever this is used for? --->
			<cfif LOCAL.rc.myEDFByte GTE LOCAL.my0x10>
				<!--- This one seems not to work yet? --->
				<cfset LOCAL.try1 = stripLongLong(myHex=LOCAL.myData)/>
				<cfset LOCAL.try2 = stripLongLong(myHex=LOCAL.myData)/>
				<!--- Seems to make everything else work --->
				<cfif LOCAL.try1 LTE 32>
					<cfset LOCAL.rc.steamid = LOCAL.try2>
				<cfelse>
					<cfset LOCAL.rc.steamid = LOCAL.try1 />
				</cfif>
				<cfset stripByte(myHex=LOCAL.myData) />
			</cfif>
			<cfif LOCAL.rc.myEDFByte GTE LOCAL.my0x40>
				<cfset LOCAL.rc.souretvport = stripShort(myHex=LOCAL.myData)/>
				<cfset LOCAL.rc.SourceTvName = stripString(myHex=LOCAL.myData)/>
			</cfif>
			<cfif LOCAL.rc.myEDFByte GTE LOCAL.my0x20>
				<cfset LOCAL.rc.keywords = stripString(myHex=LOCAL.myData)/>
			</cfif>
			<cfif LOCAL.rc.myEDFByte GTE LOCAL.my0x01>
				<cfset LOCAL.rc.GameId64bit = stripLongLong(myHex=LOCAL.myData)/>
			</cfif>

			<cfreturn LOCAL.rc />
		<cfelse>
			<cfreturn LOCAL.rc />
		</cfif>


	</cffunction>


	<!--- Private Methods - Usually sloppy helper functions to things I don't know about java --->

	<cffunction name="signedToUnsigned" returnType="numeric" access="private" output="false">
		<cfargument name="number" type="numeric" required="true" />
		<cfargument name="offset" type="numeric" required="false" default="128" hint="half your int length" />
		
		<cfset var LOCAL = structNew() />
		
		<cfif ARGUMENTS.number GT ARGUMENTS.offSet >
			<cfreturn ARGUMENTS.number - ((ARGUMENTS.offSet * 2)-1) />
		<cfelse>
			<cfreturn ARGUMENTS.number />
		</cfif>
		
		
	</cffunction>

	<cffunction name="stripByte" returnType="string" access="private" output="false" >
		<cfargument name="myHex" type="struct" required="true" />
		<cfargument name="type" type="string" default="numeric" required="false" />
		<cfargument name="signed" type="boolean" default="true" required="false" />
		
		
		<cfif ARGUMENTS.type EQ "numeric">
			<cfset LOCAL.offSet = 128 />
			
			<cfif ARGUMENTS.signed EQ TRUE>
				<cfset LOCAL.myRC = InputBaseN(stripHelper(myHex=ARGUMENTS.myHex,length=1),16) />
				<cfreturn signedToUnsigned(number=LOCAL.myRC,offset=LOCAL.offSet) />
				
			<cfelse>
				<cfreturn InputBaseN(stripHelper(myHex=ARGUMENTS.myHex,length=1),16) />			
			</cfif>
		<cfelse>
			<cfreturn hexToString(stripHelper(myHex=ARGUMENTS.myHex,length=1)) />		
		</cfif>
		
	</cffunction>


	<cffunction name="stripHelper" returnType="string" access="private" output="false">
		<cfargument name="myHex" type="struct" required="true" />
		<cfargument name="length" type="numeric" required="true" />
		
		<cfset var LOCAL = structNew() />
		
		<cfset LOCAL.myHex = ARGUMENTS.myHex.myHex />
		
		<!--- Every hex = 2 Bytes		 --->
		<cfset LOCAL.realLength = ARGUMENTS.length * 2 />
		<cfif Len(ARGUMENTS.myHex.myHex) GTE LOCAL.realLength>
			<cfif Len(ARGUMENTS.myHex.myHex) GT LOCAL.realLength>
				<cfset ARGUMENTS.myHex.myHex = Right(ARGUMENTS.myHex.myHex,Len(ARGUMENTS.myHex.myHex) - LOCAL.realLength ) />
			<cfelse>
				<cfset ARGUMENTS.myHex.myHex = "" />
			</cfif>
			
			<cfreturn Left(LOCAL.myHex,LOCAL.realLength) />			
		</cfif>

		
	</cffunction>

	<cffunction name="stripString" returnType="string" access="private" output="false" >
		<cfargument name="myHex" type="struct" required="true" />
		<cfset var LOCAL = structNew() />
		<cfset LOCAL.rc = "" />


		
		<!--- Make sure not to run into weird errors --->
		<cfset LOCAL.len = Round(Len(ARGUMENTS.myHex.myHex) / 2) />

		<cfloop from="1" to="#LOCAL.len#" index="LOCAL.i">
			<cfset LOCAL.myHexPart = stripHelper(myHex=ARGUMENTS.myHex,length=1) />
			<cfset LOCAL.numeric = InputBaseN(LOCAL.myHexPart,16) />
			
			<cfif LOCAL.numeric NEQ 0>
				<cfset LOCAL.rc = LOCAL.rc & hexToString(LOCAL.myHexPart) />
			<cfelse>
				<cfset LOCAL.myLengthCut = LOCAL.i/>
				<cfbreak />
			</cfif>
		</cfloop>

		<cfreturn LOCAL.rc />
		
	</cffunction>


	<cffunction name="readString" returntype="string" access="private" output="false">
		<cfargument name="buffer" type="any" required="true" />
		<cfset var LOCAL = structNew() />
		<cfset LOCAL.myString = "" />
		<cfset LOCAL.myLengthCut = 0 />

		<cfloop from="1" to="#ArrayLen(ARGUMENTS.buffer)#" index="LOCAL.i">
			<cfif ARGUMENTS.buffer[LOCAL.i] NEQ 0>
				<cfset LOCAL.myString = LOCAL.myString & charsetEncode(javaCast("byte[]", [ARGUMENTS.buffer[LOCAL.i]]), "utf-8") />
			<cfelse>
				<cfset LOCAL.myLengthCut = LOCAL.i/>
				<cfbreak />
			</cfif>
		</cfloop>

		<cfloop from="1" to="#LOCAL.myLengthCut#" index="LOCAL.i">
			<cfset arrayDeleteAt(ARGUMENTS.buffer,1) />
		</cfloop>


		<cfreturn LOCAL.myString />
	</cffunction>


	
	<cffunction name="stripShort" returnType="string" access="private" output="false" >
		<cfargument name="myHex" type="struct" required="true" />
		<cfset var LOCAL = structNew() />
		<cfset LOCAL.rc = "" />

		<!--- Absurd way, but it works		 --->
		<cfset LOCAL.myHexPart = stripByte(myHex=ARGUMENTS.myHex,signed=true,type="numeric") />
		<cfset LOCAL.mySecondHexPart = stripByte(myHex=ARGUMENTS.myHex,signed=true,type="numeric") />



		<!--- Java Objects for a proper short... I have no clue how to do it otherwise, but these give the proper results		 --->
		<cfset LOCAL.myByteBuffer = createObject("java","java.nio.ByteBuffer") />
		<cfset LOCAL.myByteOrder = createObject("java","java.nio.ByteOrder") />

		<cfset LOCAL.myByteBuffContents = LOCAL.myByteBuffer.Allocate(2) />
		<cfset LOCAL.myByteBuffContents.order(LOCAL.myByteOrder.LITTLE_ENDIAN) />
		<cfset LOCAL.myByteBuffContents.Put(
			javaCast("byte[]",[javaCast("int",LOCAL.myHexPart)]),
			javaCast("int",0),
			javaCast("int",1)
		)/>
		<cfset LOCAL.myByteBuffContents.Put(
			javaCast("byte[]",[javaCast("int",LOCAL.mySecondHexPart)]),
			javaCast("int",0),
			javaCast("int",1)
		)/>
		<!--- I made an error somewhere, subtract by 1 seems to fix the problem		 --->
		<cfset LOCAL.rc = LOCAL.myByteBuffContents.getShort(0) - 1 />

		<cfreturn LOCAL.rc />
		
	</cffunction>


	<cffunction name="stripLong" returnType="numeric" access="private" output="false" >
		<cfargument name="myHex" type="struct" required="true" />
				
		<cfset LOCAL.rc = 0 />
		<cfset LOCAL.myHex = stripHelper(myHex=ARGUMENTS.myHex,length=4) />

		

		<cfdump var="#InputBaseN(LOCAL.myHex,16)#"/>
		<Cfabort/>
		<cfset LOCAL.rc = LOCAL.myByteBuffContents.getLong(0)  />
		<cfreturn precisionEvaluate(LOCAL.rc - 1) />
	</cffunction>

	<!--- Documentation calls it long where it should be an INT (4Bytes instead of 8 Bytes) --->
	<cffunction name="readFloat" returntype="numeric" access="private" output="false">
		<cfargument name="buffer" type="any" required="true" />
		<cfset var LOCAL = structNew() />

		<cfset LOCAL.rc = "" />
		<cfset LOCAL.myByteBuffer = createObject("java","java.nio.ByteBuffer") />
		<cfset LOCAL.myByteOrder = createObject("java","java.nio.ByteOrder") />

		<cfset LOCAL.myByteBuffContents = LOCAL.myByteBuffer.Allocate(4) />
		<cfset LOCAL.myByteBuffContents.order(LOCAL.myByteOrder.LITTLE_ENDIAN) />
		<cfset LOCAL.myBytes = arrayNew(1) />

		<!--- Do some cool stuff with flipping in the bytearray --->
		<cfloop from="1" to="4" index="LOCAL.i">
			<cfset LOCAL.myByteBuffContents.Put(javaCast("byte[]",[javaCast("int",ARGUMENTS.buffer[1])]))/>
			<cfset arrayDeleteAt(ARGUMENTS.buffer,1) />
		</cfloop>

		<!--- Now fill it proprly --->
		<cfset LOCAL.rc = LOCAL.myByteBuffContents.getFloat(0) />
		<cfreturn	 LOCAL.rc />

	</cffunction>

	<cffunction name="stripLongLong" returnType="numeric" access="private" output="false" >
		<cfargument name="myHex" type="struct" required="true" />
				
		<cfset LOCAL.rc = 0 />
		<cfset LOCAL.myByteBuffer = createObject("java","java.nio.ByteBuffer") />
		<cfset LOCAL.myByteOrder = createObject("java","java.nio.ByteOrder") />

		<cfset LOCAL.myByteBuffContents = LOCAL.myByteBuffer.Allocate(8) />
		<cfset LOCAL.myByteBuffContents.order(LOCAL.myByteOrder.LITTLE_ENDIAN) />
		<cfloop from="1" to="8" index="LOCAL.i">
			<cfset LOCAL.myByteBuffContents.Put(
				javaCast("byte[]",[javaCast("int",stripByte(myHex=ARGUMENTS.myHex,signed=true,type='numeric'))])
			)/>							
		</cfloop>


		<cfset LOCAL.rc = LOCAL.myByteBuffContents.getLong(0)  />
		<cfreturn precisionEvaluate(LOCAL.rc - 1) />
	</cffunction>

	<!--- Documentation calls it long where it should be an INT (4Bytes instead of 8 Bytes) --->
	<cffunction name="readLongLong" returntype="numeric" access="private" output="false">
		<cfargument name="buffer" type="any" required="true" />
		<cfset var LOCAL = structNew() />

		<cfset LOCAL.rc = "" />
		<cfset LOCAL.myByteBuffer = createObject("java","java.nio.ByteBuffer") />
		<cfset LOCAL.myByteOrder = createObject("java","java.nio.ByteOrder") />

		<cfset LOCAL.myByteBuffContents = LOCAL.myByteBuffer.Allocate(8) />
		<cfset LOCAL.myByteBuffContents.order(LOCAL.myByteOrder.LITTLE_ENDIAN) />
		<cfloop from="1" to="8" index="LOCAL.i">
			<cfset LOCAL.myByteBuffContents.Put(
			javaCast("byte[]",[javaCast("int",ARGUMENTS.buffer[1])])
			)/>
			<cfset arrayDeleteAt(ARGUMENTS.buffer,1) />
		</cfloop>


		<cfset LOCAL.rc = LOCAL.myByteBuffContents.getLong(0) />
		<cfreturn	 LOCAL.rc />

	</cffunction>


	<cffunction name="readChar" returntype="numeric" access="private" output="false">
		<cfargument name="buffer" type="any" required="true" />
		<cfset var LOCAL = structNew() />

	</cffunction>



	<cffunction name="convertNumberToChar" returntype="string" access="private">
		<cfargument name="ByteNumber" type="numeric" required="true"/>

		<cfset LOCAL.myByte = javaCast("byte[]",[javaCast("int",ARGUMENTS.ByteNumber)])/>
		<cfreturn charsetEncode(LOCAL.myByte,'utf-8') />

	</cffunction>

	<cffunction name="cutByteArrayToString" returntype="string" access="private">
		<cfargument name="byteArray" 	type="any" required="true" />
		<cfargument name="startPos" 	type="numeric" required="true" />
		<cfargument name="endPos" 		type="numeric" required="true" />

		<cfset var LOCAL = structNew() />
		<cfset LOCAL.rc = "" />
		<cfset LOCAL.myByteBuffer = createObject("java","java.nio.ByteBuffer") />
		<cfset LOCAL.myByteBuffContents = LOCAL.myByteBuffer.Allocate((ARGUMENTS.endPos - ARGUMENTS.startPos) + 1) />

		<cfloop from="#ARGUMENTS.startPos#" to="#ARGUMENTS.endPos#" index="LOCAL.i">
			<cfset LOCAL.myByteBuffContents.Put(
				javaCast("byte[]",[javaCast("int",ARGUMENTS.byteArray[LOCAL.i])]),
				javaCast("int",0),
				javaCast("int",1)
			)/>
		</cfloop>
		<cfreturn charsetEncode(LOCAL.myByteBuffContents.array(),"utf-8") />
	</cffunction>

	<cffunction name="cutByteArrayToShort" returntype="string" access="private">
		<cfargument name="byteArray" 	type="any" required="true" />
		<cfargument name="startPos" 	type="numeric" required="true" />

		<cfset var LOCAL = structNew() />
		<cfset LOCAL.rc = "" />
		<cfset LOCAL.myByteBuffer = createObject("java","java.nio.ByteBuffer") />
		<cfset LOCAL.myByteOrder = createObject("java","java.nio.ByteOrder") />
		<cfset LOCAL.endPos = ARGUMENTS.startPos + 1 />
		<cfset LOCAL.myByteBuffContents = LOCAL.myByteBuffer.Allocate(2) />
		<cfset LOCAL.myByteBuffContents.order(LOCAL.myByteOrder.LITTLE_ENDIAN) />
		<cfset LOCAL.myByteBuffContents.Put(
			javaCast("byte[]",[javaCast("int",ARGUMENTS.byteArray[ARGUMENTS.startPos])]),
			javaCast("int",0),
			javaCast("int",1)
		)/>
		<cfset LOCAL.myByteBuffContents.Put(
			javaCast("byte[]",[javaCast("int",ARGUMENTS.byteArray[LOCAL.endPos])]),
			javaCast("int",0),
			javaCast("int",1)
		)/>

		<cfreturn LOCAL.myByteBuffContents.getShort(0) />
	</cffunction>

	<!--- Helper function to make me find the next string end --->
	<cffunction name="checkForNextStringEnd" returntype="numeric" access="private">
		<cfargument name="byteArray" type="any" required="true" />
		<cfargument name="startPos" type="numeric" required="true" />

		<cfset LOCAL.rc = -1 />

		<cfloop from="#ARGUMENTS.startPos#" to="#ArrayLen(ARGUMENTS.byteArray)#" index="LOCAL.i">
			<cfif ARGUMENTS.byteArray[LOCAL.i] EQ 0>
				<cfreturn LOCAL.i />
			</cfif>
		</cfloop>

		<cfreturn LOCAL.rc />
	</cffunction>
	
	
	<cfscript>
		function base64ToHex( String base64Value ){
	
			 var binaryValue = binaryDecode( base64Value, "base64" );
			 var hexValue = binaryEncode( binaryValue, "hex" );
	
			 return( lcase( hexValue ) );
	
		 }
	
	
		 function base64ToString( String base64Value ){
	
			 var binaryValue = binaryDecode( base64Value, "base64" );
			 var stringValue = toString( binaryValue );
	
			 return( stringValue );
	
		 }
	
	
		 function hexToBase64( String hexValue ){
	
			 var binaryValue = binaryDecode( hexValue, "hex" );
			 var base64Value = binaryEncode( binaryValue, "base64" );
	
			 return( base64Value );
	
		 }
	
	
		 function hexToString( String hexValue ){
	
			 var binaryValue = binaryDecode( hexValue, "hex" );
			 var stringValue = toString( binaryValue );
	
			 return( stringValue );
	
		 }
	
	
		 function stringToBase64( String stringValue ){
	
			 var binaryValue = stringToBinary( stringValue );
			 var base64Value = binaryEncode( binaryValue, "base64" );
	
			 return( base64Value );
	
		 }
	
	
		 function stringToBinary( String stringValue ){
	
			 var base64Value = toBase64( stringValue );
			 var binaryValue = toBinary( base64Value );
	
			 return( binaryValue );
	
		 }
	
	
		 function stringToHex( String stringValue ){
	
			 var binaryValue = stringToBinary( stringValue );
			 var hexValue = binaryEncode( binaryValue, "hex" );
	
			 return( lcase( hexValue ) );
	
		 }
		
	</cfscript>
</cfcomponent>


