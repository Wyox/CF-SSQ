<cfcomponent displayname="SourceMod Server Queries and Rcon" hint="Used to get information from some types of gameservers">
	<!--- Might be good to know
	Made by: Ivo de Bruijn

	Description: This is a SourceMod Query CFC that talks to Source servers to get information.

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


	<cffunction name="doRequest" returntype="struct" output="false" access="public">
		<cfargument name="ip" type="string" required="true" />
		<cfargument name="port" type="numeric" required="true" />
		<cfargument name="message" type="any" required="true" />
		<cfset var LOCAL = structNew() />
		<cfset LOCAL.rc = structNew() />
		<cfset LOCAL.rc.success = false />
		<cfset LOCAL.rc.data = "" />
		<cfset LOCAL.rc.dataByte = javaCast("byte[]",[0]) />

		<!--- Our address --->
		<cfset LOCAL.myPort = javaCast("int",ARGUMENTS.port + 10000 + ceiling(RandRange(1,1000))) />
		<cfset LOCAL.myNetAddress = createObject("java","java.net.InetAddress").getLocalHost() />
		<!--- Remote address --->
		<cfset LOCAL.remotePort = javaCast("int",ARGUMENTS.port) />
		<cfset LOCAL.remoteInetAddress = createObject("java","java.net.InetAddress").getByName(javaCast("string",ARGUMENTS.ip))/>

		<!--- Create DatagramSocket - We need to listen to something --->
		<cfset LOCAL.mySocket = createObject("java","java.net.DatagramSocket").init(
			LOCAL.myPort,myNetAddress)/>

		<cftry>
			<cfset LOCAL.myPacket = createObject("java","java.net.DatagramPacket").init(
					ARGUMENTS.message,
					javaCast("int",ArrayLen(ARGUMENTS.message)),
					LOCAL.remoteInetAddress,
					LOCAL.remotePort
				)/>
			<cfset LOCAL.mySocket.send(LOCAL.myPacket) />
				
			<!--- Wait for response --->
			<cfset LOCAL.myResponse = createObject("java","java.net.DatagramPacket").init(charsetDecode(repeatString(" ", 1024),"utf-8"),javaCast("int",1024)) />
			<!--- Wait 5 seconds --->
			<cfset LOCAL.mySocket.setSoTimeout(javaCast("int",5000)) />
			<!--- Shit we got stuff --->
			<cfset LOCAL.mySocket.receive(LOCAL.myResponse) />
			<!--- Get the data --->
			<cfset LOCAL.myData = LOCAL.myResponse.getData() />

			<!--- Place them in the return stuff --->
			<cfset LOCAL.rc.dataByte = THIS.convertByteArrayToCFArray(byteArray=LOCAL.myData,maxLength=LOCAL.myResponse.getLength()) />
			<cfset LOCAL.isMultiPacket = THIS.readByte(buffer=LOCAL.rc.dataByte) />
			<cfset THIS.readByte(buffer=LOCAL.rc.dataByte) />
			<cfset THIS.readByte(buffer=LOCAL.rc.dataByte) />
			<cfset THIS.readByte(buffer=LOCAL.rc.dataByte) />
			<cfset LOCAL.rc.multiPacketArray = arrayNew(1) />
			<cfset LOCAL.shouldGetMore = false />
			<cfset LOCAL.useCompression = false />


			<cfif LOCAL.isMultiPacket EQ -2>
				<cfset LOCAL.tempSortingArray = structNew() />

				<cfset LOCAL.shouldGetMore = true />
				<!--- Read out multipacket rules --->
				<cfset LOCAL.rc.multiPacketId = THIS.readLong(buffer=LOCAL.rc.dataByte) />
				<cfset LOCAL.rc.totalPackets = THIS.readByte(buffer=LOCAL.rc.dataByte) />
				<cfset LOCAL.rc.packetNumber = THIS.readByte(buffer=LOCAL.rc.dataByte) />
				<cfset LOCAL.rc.packetSize	= THIS.readShort(buffer=LOCAL.rc.dataByte) />
				<cfif LOCAL.rc.multiPacketId GT 2147483648>
					<cfset LOCAL.useCompression = true />
				</cfif>
				<!--- Read out compression stuff --->
				<cfif LOCAL.useCompression EQ true>
					<cfset LOCAL.myPacketSize =  THIS.readLong(buffer=LOCAL.myData) />
					<cfset LOCAL.myCRC32CheckSum = THIS.readLong(buffer=LOCAL.myData) />
				</cfif>
				<cfset LOCAL.tempSortingArray[LOCAL.rc.packetNumber + 1] = LOCAL.rc.dataByte />

			</cfif>
			<!--- Use compression 2147483648 --->
			<cfloop condition="#LOCAL.shouldGetMore EQ true#">

				<!--- Wait for response --->
				<cfset LOCAL.myResponse = createObject("java","java.net.DatagramPacket").init(charsetDecode(repeatString(" ", 1024),"utf-8"),javaCast("int",1024)) />
				<!--- Wait 5 seconds --->
				<cfset LOCAL.mySocket.setSoTimeout(javaCast("int",5000)) />
				<!--- Shit we got stuff --->
				<cfset LOCAL.mySocket.receive(LOCAL.myResponse) />
				<!--- Get the data --->
				<cfset LOCAL.myDataByte = LOCAL.myResponse.getData() />
				<!--- Something weird is going on here --->
				<cfset LOCAL.myData = THIS.convertByteArrayToCFArray(byteArray=LOCAL.myDataByte,maxLength=LOCAL.myResponse.getLength()) />
				<cfset LOCAL.isMultiPacket = THIS.readByte(buffer=LOCAL.myData) />
				<!--- Rip off useless FFFFFF --->
				<cfset THIS.readByte(buffer=LOCAL.myData) />
				<cfset THIS.readByte(buffer=LOCAL.myData) />
				<cfset THIS.readByte(buffer=LOCAL.myData) />

				<cfset LOCAL.multiPacketId = THIS.readLong(buffer=LOCAL.myData) />
				<cfset LOCAL.totalPackets = THIS.readByte(buffer=LOCAL.myData) />
				<cfset LOCAL.packetNumber = THIS.readByte(buffer=LOCAL.myData) />
				<cfset LOCAL.packetSize		= THIS.readShort(buffer=LOCAL.myData) />

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
					<cfset LOCAL.rc.dataByte = THIS.arrayMerge(array1=LOCAL.rc.dataByte,array2=LOCAL.tempSortingArray[LOCAL.i]) />
				</cfloop>
				<!--- wtf? --->
				<cfset LOCAL.isMultiPacket = THIS.readByte(buffer=LOCAL.rc.dataByte) />
				<cfset THIS.readByte(buffer=LOCAL.rc.dataByte) />
				<cfset THIS.readByte(buffer=LOCAL.rc.dataByte) />
				<cfset THIS.readByte(buffer=LOCAL.rc.dataByte) />				
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
				<!--- <cfabort /> --->
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

		<cfset LOCAL.myChallengeNumber = THIS.getChallengeNumber(ip=ARGUMENTS.ip,port=ARGUMENTS.port,startHex="55") />

		<!--- Get players --->
		<cfif LOCAL.myChallengeNumber GT 0 >	
			<!--- Challange Header Byte (0x55)--->
			<cfset LOCAL.myHeaderByte = THIS.convertHexToByte(myHex="55") />		
			<cfset LOCAL.myEmptyByte = THIS.convertHexToByte(myHex="FF") />

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
			<cfset LOCAL.myContents = THIS.doRequest(ip=ARGUMENTS.ip,port=ARGUMENTS.port,message=LOCAL.myByteContentsArray) />		

			<cfif LOCAL.myContents.success EQ true>
				<cfset LOCAL.myData =LOCAL.myContents.dataByte />
				<!--- Strip off useless bytes --->
				<cfset LOCAL.myHeader = Chr(THIS.readByte(buffer=LOCAL.myData)) />

				<cfif LOCAL.myHeader EQ "D">
					
				
					<cfset LOCAL.rc.PlayerAmount = THIS.readByte(buffer=LOCAL.myData) />

					<cfloop from="1" to="#LOCAL.rc.PlayerAmount#" index="LOCAL.i">
						<cfset LOCAL.playerStruct = structNew() />
						<cfset LOCAL.playerStruct['index'] = THIS.readByte(buffer=LOCAL.myData)/>
						<cfset LOCAL.playerStruct['name'] = THIS.readString(buffer=LOCAL.myData)/>

						<cfset LOCAL.playerStruct['score'] = THIS.readShort(buffer=LOCAL.myData)/>
						<cfset LOCAL.playerStruct['tryFloat'] = arrayNew(1) />
						<cfset THIS.readByte(buffer=LOCAL.myData)/>
						<cfset THIS.readByte(buffer=LOCAL.myData)/>
 						<cfset LOCAL.playerStruct['duration'] = THIS.readFloat(buffer=LOCAL.myData)/>

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
		<!--- Challange Header Byte (0x55)--->
		<cfset LOCAL.myHeaderByte = THIS.convertHexToByte(myHex=ARGUMENTS.startHex) />		
		<cfset LOCAL.myEmptyByte = THIS.convertHexToByte(myHex="FF") />

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

		<!--- T --->
		<cfset LOCAL.myByteBuffContents.Put(
			LOCAL.myHeaderByte,
			javaCast("int",0),
			javaCast("int",1)
		)/>
		<!--- FF --->
		<cfloop from="1" to="4" index="LOCAL.i">
			<cfset LOCAL.myByteBuffContents.Put(
				LOCAL.myEmptyByte,
				javaCast("int",0),
				javaCast("int",1)
			)/>			
		</cfloop>		


		<cfset LOCAL.myByteContentsArray = LOCAL.myByteBuffContents.array() />
		<cfset LOCAL.myContents = THIS.doRequest(ip=ARGUMENTS.ip,port=ARGUMENTS.port,message=LOCAL.myByteContentsArray) />		
		<cfset LOCAL.myData = LOCAL.myContents.dataByte />

		<!--- Strip off useless bytes --->
		<cfset LOCAL.myHeader = Chr(THIS.readByte(buffer=LOCAL.myData)) />

		
		<!--- We can get ourselfs a challange number --->
		<cfif LOCAL.myContents.success EQ true AND LOCAL.myHeader EQ "A">
			<cfset LOCAL.rc =  THIS.readLong(buffer=LOCAL.myData) />
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

		<cfset LOCAL.myChallengeNumber = THIS.getChallengeNumber(ip=ARGUMENTS.ip,port=ARGUMENTS.port,startHex="56") />

		<!--- Get players --->
		<cfif LOCAL.myChallengeNumber GT 0 >	
			<!--- Challange Header Byte (0x55)--->
			<cfset LOCAL.myHeaderByte = THIS.convertHexToByte(myHex="56") />		
			<cfset LOCAL.myEmptyByte = THIS.convertHexToByte(myHex="FF") />

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

			<cfset LOCAL.myContents = THIS.doRequest(ip=ARGUMENTS.ip,port=ARGUMENTS.port,message=LOCAL.myByteContentsArray) />		
			<cfif LOCAL.myContents.success EQ true>
				<cfset LOCAL.rc.connected = true />
				<cfset LOCAL.myData = LOCAL.myContents.dataByte />
				<cfset LOCAL.myHeader = Chr(THIS.readByte(buffer=LOCAL.myData)) /> 
				<cfset LOCAL.rc.amountOfRules = THIS.readShort(buffer=LOCAL.myData) />

				<cfset LOCAL.rc.rules = structNew() />

				<cfif LOCAL.myHeader EQ "E">
					<cfset LOCAL.thisHasRules = true />
					<cfset LOCAL.maxLoopCount = 500 />
					<cfset LOCAL.count = 0 />
					<cfloop from="1" to="#LOCAL.rc.amountOfRules#" index="LOCAL.i">
						<cfset LOCAL.ruleName = THIS.readString(buffer=LOCAL.myData) />
						<cfset LOCAL.ruleVariable = THIS.readString(buffer=LOCAL.myData) />
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
		<!--- Byte for A2S_INFO --->
		<cfset LOCAL.myHeaderByte = THIS.convertHexToByte(myHex="54") />
		<!--- Empty byte FF --->
		<cfset LOCAL.emptyByte = javaCast('byte[]',[255]) />
		<!--- We need this to end the packet --->
		<cfset LOCAL.nulTerminator = javaCast('byte[]',[0]) />

		<!--- Message is the type --->
		<cfset LOCAL.myMessage = ARGUMENTS.type />

		<!--- Concat all bytes --->
		<cfset LOCAL.myByteBuffer = createObject("java","java.nio.ByteBuffer") />
		<!--- We need FF FF FF FF HEADERBYTE MESSAGEBYTES TERMINATOR --->
		<cfset LOCAL.myByteLength = 4 + 1 + Len(LOCAL.myMessage) + 1 />
		<cfset LOCAL.myByteBuffContents = LOCAL.myByteBuffer.Allocate(LOCAL.myByteLength) />

		<!--- FF --->
		<cfloop from="1" to="4" index="LOCAL.i">
			<cfset LOCAL.myByteBuffContents.Put(
				LOCAL.emptyByte,
				javaCast("int",0),
				javaCast("int",1)
			)/>			
		</cfloop>

		<!--- T --->
		<cfset LOCAL.myByteBuffContents.Put(
			LOCAL.myHeaderByte,
			javaCast("int",0),
			javaCast("int",1)
		)/>

		<!--- Message --->
		<cfset LOCAL.myByteBuffContents.Put(
			charsetDecode(LOCAL.myMessage,'utf-8'),
			javaCast("int",0),
			javaCast("int",Len(LOCAL.myMessage))
		)/>		
		<!--- Terminator --->
		<cfset LOCAL.myByteBuffContents.Put(
			LOCAL.nulTerminator,
			javaCast("int",0),
			javaCast("int",1)
		)/>	
		<!--- Byte array :) --->
		<cfset LOCAL.myByteContentsArray = LOCAL.myByteBuffContents.array() />
		<cfset LOCAL.myContents = THIS.doRequest(ip=ARGUMENTS.ip,port=ARGUMENTS.port,message=LOCAL.myByteContentsArray) />
		<cfset structDelete(LOCAL,"myByteContentsArray") />
		<cfset structDelete(LOCAL,"myByteBuffContents") />
		<cfset structDelete(LOCAL,"myByteBuffer") />

		<cfset LOCAL.myData = LOCAL.myContents.dataByte />

		<!--- Strip off useless bytes --->
		<cfset LOCAL.uselessByte = THIS.readByte(buffer=LOCAL.myData)/>
		<cfset LOCAL.uselessByte = THIS.readByte(buffer=LOCAL.myData)/>
		<cfset LOCAL.uselessByte = THIS.readByte(buffer=LOCAL.myData)/>
		<cfset LOCAL.uselessByte = THIS.readByte(buffer=LOCAL.myData)/>

		<cfset LOCAL.rc.header 		= Chr(THIS.readByte(buffer=LOCAL.myData)) />
		<cfset LOCAL.rc.protocol 	= THIS.readByte(buffer=LOCAL.myData) />
		<cfset LOCAL.rc.name 		= THIS.readString(buffer=LOCAL.myData) />
		<cfset LOCAL.rc.map 		= THIS.readString(buffer=LOCAL.myData) />
		<cfset LOCAL.rc.folder 		= THIS.readString(buffer=LOCAL.myData) /> 
		<cfset LOCAL.rc.game 		= THIS.readString(buffer=LOCAL.myData) /> 

		<cfset LOCAL.rc.gameid 		= THIS.readShort(buffer=LOCAL.myData) /> 
		<cfset LOCAL.rc.players 	= THIS.readByte(buffer=LOCAL.myData) /> 
		<cfset LOCAL.rc.maxPlayers 	= THIS.readByte(buffer=LOCAL.myData) /> 
		<cfset LOCAL.rc.bots 		= THIS.readByte(buffer=LOCAL.myData) /> 
		<cfset LOCAL.rc.servertype 	= Chr(THIS.readByte(buffer=LOCAL.myData)) /> 
		<cfset LOCAL.rc.environment	= Chr(THIS.readByte(buffer=LOCAL.myData)) /> 
		<cfset LOCAL.rc.visibility 	= THIS.readByte(buffer=LOCAL.myData) /> 
		<cfset LOCAL.rc.vac 		= THIS.readByte(buffer=LOCAL.myData) /> 

		<!--- Coldfusion doesn't support Byte comparison by default so I hope this is correct --->

		<!--- EDF (Extra Data Flag comparison) --->
		<cfset LOCAL.myEDFByte = THIS.readByte(buffer=LOCAL.myData) />

		<!--- Compare --->
		<cfset LOCAL.my0x80 = THIS.convertHexToByte(myHex="80")[1] + 256 />
		<cfset LOCAL.my0x40 = THIS.convertHexToByte(myHex="40")[1] />
		<cfset LOCAL.my0x20 = THIS.convertHexToByte(myHex="20")[1] />
		<cfset LOCAL.my0x10 = THIS.convertHexToByte(myHex="10")[1] />
		<cfset LOCAL.my0x01 = THIS.convertHexToByte(myHex="01")[1] />

		<!--- Current one is Servers Game Port --->
		<cfif LOCAL.myEDFByte GTE LOCAL.my0x80>
			<cfset LOCAL.rc.gameport = THIS.readShort(buffer=LOCAL.myData)/>
		</cfif>
		<!--- What ever this is used for? --->
		<cfif LOCAL.myEDFByte GTE LOCAL.my0x10>
			<!--- This one seems not to work yet? --->
			<cfset LOCAL.try1 = THIS.readLongLong(buffer=LOCAL.myData)/>
			<cfset LOCAL.try2 = THIS.readLongLong(buffer=LOCAL.myData)/>
			<!--- Seems to make everything else work --->
			<cfif LOCAL.try1 LTE 32>
				<cfset LOCAL.rc.steamid = LOCAL.try2>
			<cfelse>
				<cfset LOCAL.rc.steamid = LOCAL.try1 />
			</cfif>			
			<cfset THIS.readByte(buffer=LOCAL.myData) />
		</cfif>
		<cfif LOCAL.myEDFByte GTE LOCAL.my0x40>
			<cfset LOCAL.rc.souretvport = THIS.readShort(buffer=LOCAL.myData)/>
			<cfset LOCAL.rc.SourceTvName = THIS.readString(buffer=LOCAL.myData)/>
		</cfif>				
		<cfif LOCAL.myEDFByte GTE LOCAL.my0x20>
			<cfset LOCAL.rc.keywords = THIS.readString(buffer=LOCAL.myData)/>
		</cfif>				
		<cfif LOCAL.myEDFByte GTE LOCAL.my0x01>
			<cfset LOCAL.rc.GameId64bit = THIS.readLongLong(buffer=LOCAL.myData)/>
		</cfif>			

		<cfif LOCAL.myContents.success EQ TRUE>
			<cfreturn LOCAL.rc />
		<cfelse>
			<cfreturn LOCAL.rc />
		</cfif>


	</cffunction>


	<!--- Private Methods - Usually sloppy helper functions to things I don't know about java --->


	<!--- to add support for CF10 and before --->
	<cffunction name="arrayMerge" returntype="any" access="private" output="false">
		<cfargument name="array1" required="true" type="array"/>
		<cfargument name="array2" required="true" type="array"/>

		<cfset var LOCAL = structNew() />
		<cfset LOCAL.rc = ARGUMENTS.array1 />

		<cfloop from="1" to="#ArrayLen(ARGUMENTS.array2)#" index="LOCAL.i">
			<cfset arrayAppend(LOCAL.rc,ARGUMENTS.array2[LOCAL.i]) />
		</cfloop>

		<cfreturn LOCAL.rc />
	</cffunction>

	<cffunction name="convertByteArrayToCFArray" returntype="array" access="public" output="false">
		<cfargument name="byteArray" required="true" type="any" />
		<cfargument name="maxLength" required="false" type="numeric" default="0" />
		<cfset LOCAL.rc = arrayNew(1) />

		<cfif ARGUMENTS.maxLength EQ 0>
			<cfset LOCAL.maxLength = ArrayLen(ARGUMENTS.byteArray) />
		<cfelse>
			<cfset LOCAL.maxLength = ARGUMENTS.maxLength />
		</cfif>
		<cfloop from="1" to="#LOCAL.maxLength#" index="LOCAL.i">
			<cfset arrayAppend(LOCAL.rc,ARGUMENTS.byteArray[LOCAL.i]) />
		</cfloop>

		<cfreturn LOCAL.rc />
	</cffunction>

	<cffunction name="cutByteArray" returntype="any" access="public" output="false">
		<cfargument name="buffer" type="any" required="true" />
		<cfargument name="length" type="numeric" required="true" />

		<cfset var LOCAL = structNew() />



		<cfreturn />
	</cffunction>

	<cffunction name="convertHexToByte" returntype="any" access="private" output="false">
		<cfargument name="myHex" type="string" required="true" />
		<cfset var LOCAL = structNew() />

		<cfset LOCAL.myByteNumber = inputBaseN(ARGUMENTS.myHex,16) />

		<cfset LOCAL.myByte = javaCast("byte[]",[LOCAL.myByteNumber]) />

		<cfreturn LOCAL.myByte />
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

	<cffunction name="readByte" returntype="numeric" access="private" output="false">
		<cfargument name="buffer" type="any" required="true" />
		<cfset var LOCAL = structNew() />
		<cfset LOCAL.myByte = ARGUMENTS.buffer[1] />
		<cfset arrayDeleteAt(ARGUMENTS.buffer,1) />
		<cfreturn LOCAL.myByte />
	</cffunction>

	<cffunction name="readShort" returntype="numeric" access="private" output="false">
		<cfargument name="buffer" type="any" required="true" />
		<cfset var LOCAL = structNew() />

		<cfset LOCAL.rc = "" />
		<cfset LOCAL.myByteBuffer = createObject("java","java.nio.ByteBuffer") />
		<cfset LOCAL.myByteOrder = createObject("java","java.nio.ByteOrder") />

		<cfset LOCAL.myByteBuffContents = LOCAL.myByteBuffer.Allocate(2) />
		<cfset LOCAL.myByteBuffContents.order(LOCAL.myByteOrder.LITTLE_ENDIAN) />		
		<cfset LOCAL.myByteBuffContents.Put(
			javaCast("byte[]",[javaCast("int",ARGUMENTS.buffer[1])]),
			javaCast("int",0),
			javaCast("int",1)
		)/>
		<cfset arrayDeleteAt(ARGUMENTS.buffer,1) />
		<cfset LOCAL.myByteBuffContents.Put(
			javaCast("byte[]",[javaCast("int",ARGUMENTS.buffer[1])]),
			javaCast("int",0),
			javaCast("int",1)
		)/>
		<cfset arrayDeleteAt(ARGUMENTS.buffer,1) />
		<cfset LOCAL.rc = LOCAL.myByteBuffContents.getShort(0) />
		<cfreturn  LOCAL.rc />

	</cffunction>

	<!--- Documentation calls it long where it should be an INT (4Bytes instead of 8 Bytes) --->
	<cffunction name="readLong" returntype="numeric" access="private" output="false">
		<cfargument name="buffer" type="any" required="true" />
		<cfset var LOCAL = structNew() />

		<cfset LOCAL.rc = "" />
		<cfset LOCAL.myByteBuffer = createObject("java","java.nio.ByteBuffer") />
		<cfset LOCAL.myByteOrder = createObject("java","java.nio.ByteOrder") />

		<cfset LOCAL.myByteBuffContents = LOCAL.myByteBuffer.Allocate(8) />
		<cfset LOCAL.myByteBuffContents.order(LOCAL.myByteOrder.LITTLE_ENDIAN) />		
		<cfset LOCAL.myBytes = arrayNew(1) />

		<!--- Do some cool stuff with flipping in the bytearray --->
		<cfloop from="1" to="4" index="LOCAL.i">
			<cfset LOCAL.myByteBuffContents.position(4 - LOCAL.i) />
			<cfset LOCAL.myByteBuffContents.Put(javaCast("byte[]",[javaCast("int",ARGUMENTS.buffer[1])]))/>
			<cfset arrayDeleteAt(ARGUMENTS.buffer,1) />
		</cfloop>

		<!--- Now fill it proprly --->
		<cfset LOCAL.rc = LOCAL.myByteBuffContents.getLong(0) />
		<cfreturn  LOCAL.rc />

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
		<cfreturn  LOCAL.rc />

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
		<cfreturn  LOCAL.rc />

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
</cfcomponent>


