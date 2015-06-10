//
//  MIDIManager.swift
//  Swift2MIDI
//
//  Created by Gene De Lisa on 6/9/15.
//  Copyright © 2015 Gene De Lisa. All rights reserved.
//

import Foundation
import CoreMIDI
import CoreAudio
import AudioToolbox

/// The `Singleton` instance
private let MIDIManagerInstance = MIDIManager()

/**
# MIDIManager

> Here is an initial cut at using the new Swift 2.0 MIDI frobs.

*/
class MIDIManager : NSObject {
    
    class var sharedInstance:MIDIManager {
        return MIDIManagerInstance
    }
    
    var midiClient = MIDIClientRef()
    
    var outputPort = MIDIPortRef()
    
    var inputPort = MIDIPortRef()

    var destEndpointRef = MIDIEndpointRef()
    
    var midiInputPortref = MIDIPortRef()
    
    var musicPlayer:MusicPlayer?
    
    var processingGraph = AUGraph()
    
    var samplerUnit = AudioUnit()
    
    
    /**
    This will initialize the midiClient, outputPort, and inputPort variables.
    */
    
    func initMIDI(midiNotifier: MIDINotifyBlock? = nil, reader: MIDIReadBlock? = nil) {
        enableNetwork()
        
        var notifyBlock: MIDINotifyBlock
        
        if midiNotifier != nil {
            notifyBlock = midiNotifier!
        } else {
            notifyBlock = MyMIDINotifyBlock
        }
        
        var readBlock: MIDIReadBlock
        if reader != nil {
            readBlock = reader!
        } else {
            readBlock = MyMIDIReadBlock
        }
        
        var status = OSStatus(noErr)
        status = MIDIClientCreateWithBlock("MyMIDIClient", &midiClient, notifyBlock)
        
        if status == OSStatus(noErr) {
            print("created client")
        } else {
            print("error creating client : \(status)")
            showError(status)
        }
        if status == OSStatus(noErr) {
            
            status = MIDIInputPortCreateWithBlock(midiClient, "MyClient In", &inputPort, readBlock)
            if status == OSStatus(noErr) {
                print("created input port")
            } else {
                print("error creating input port : \(status)")
                showError(status)
            }
            
            
            status = MIDIOutputPortCreate(midiClient,
                "My Output Port",
                &outputPort)
            if status == OSStatus(noErr) {
                print("created output port \(outputPort)")
            } else {
                print("error creating output port : \(status)")
                showError(status)
            }
            
            
            status = MIDIDestinationCreateWithBlock(midiClient,
                "Virtual Dest",
                &destEndpointRef,
                readBlock)
            
            // or if you want to use a closure
//            status = MIDIDestinationCreateWithBlock(midiClient,
//                "Virtual Dest",
//                &destEndpointRef,
//                { (packetList:UnsafePointer<MIDIPacketList>, src:UnsafeMutablePointer<Void>) -> Void in
//                    
//                    let packets = packetList.memory
//                    let packet:MIDIPacket = packets.packet.0
//                    
//                    // do the loop here...
//                    
//                    self.handle(packet)
//                    
//            })
            
            if status != noErr {
                print("error creating virtual destination: \(status)")
            } else {
                print("midi virtual destination created \(destEndpointRef)")
            }
            
            
            
            connectSourcesToInputPort()
            initGraph()
            
        }
        

    }
    
    
    func initGraph() {
        augraphSetup()
        graphStart()
        // after the graph starts
        loadSF2Preset(0)
        CAShow(UnsafeMutablePointer<MusicSequence>(self.processingGraph))
    }
    
    
    // typealias MIDIReadBlock = (UnsafePointer<MIDIPacketList>, UnsafeMutablePointer<Void>) -> Void
    
    func MyMIDIReadBlock(packetList: UnsafePointer<MIDIPacketList>, srcConnRefCon: UnsafeMutablePointer<Void>) -> Void {

        //debugPrint("MyMIDIReadBlock \(packetList)")
        
        let packets = packetList.memory

        let packet:MIDIPacket = packets.packet.0

        // don't do this
//        print("packet \(packet)")
        
        var ap = UnsafeMutablePointer<MIDIPacket>.alloc(1)
        ap.initialize(packet)

        for _ in 0 ..< packets.numPackets {

            let p = ap.memory
            print("timestamp \(p.timeStamp)", appendNewline:false)
            var hex = String(format:"0x%X", p.data.0)
            print(" \(hex)", appendNewline:false)
            hex = String(format:"0x%X", p.data.1)
            print(" \(hex)", appendNewline:false)
            hex = String(format:"0x%X", p.data.2)
            print(" \(hex)")

            handle(p)
            
            ap = MIDIPacketNext(ap)

        }
        
    }

    func handle(packet:MIDIPacket) {
        
        let status = packet.data.0
        let d1 = packet.data.1
        let d2 = packet.data.2
        let rawStatus = status & 0xF0 // without channel
        let channel = status & 0x0F
        
        switch rawStatus {
            
        case 0x80:
            print("Note off. Channel \(channel) note \(d1) velocity \(d2)")
            // forward to sampler
            playNoteOff(UInt32(channel), noteNum: UInt32(d1))
            
        case 0x90:
            print("Note on. Channel \(channel) note \(d1) velocity \(d2)")
            // forward to sampler
            playNoteOn(UInt32(channel), noteNum:UInt32(d1), velocity: UInt32(d2))
            
        case 0xA0:
            print("Polyphonic Key Pressure (Aftertouch). Channel \(channel) note \(d1) pressure \(d2)")
            
        case 0xB0:
            print("Control Change. Channel \(channel) controller \(d1) value \(d2)")
            
        case 0xC0:
            print("Program Change. Channel \(channel) program \(d1)")
            
        case 0xD0:
            print("Channel Pressure (Aftertouch). Channel \(channel) pressure \(d1)")
            
        case 0xE0:
            print("Pitch Bend Change. Channel \(channel) lsb \(d1) msb \(d2)")
            
        default: print("Unhandled message \(status)")
        }

        
    }
    
    //typealias MIDINotifyBlock = (UnsafePointer<MIDINotification>) -> Void
    func MyMIDINotifyBlock(midiNotification: UnsafePointer<MIDINotification>) {
        print("got a MIDINotification!")
        
        let notification = midiNotification.memory
        print("MIDI Notify, messageId= \(notification.messageID)")
        print("MIDI Notify, messageSize= \(notification.messageSize)")
        
        // values are now an enum!
        
        switch (notification.messageID) {
        case .MsgSetupChanged:
            print("MIDI setup changed")
            break
            
            //TODO: so how to "downcast" to MIDIObjectAddRemoveNotification
        case .MsgObjectAdded:
            
            print("added")
            
            var mem = midiNotification.memory
            withUnsafePointer(&mem) { ptr -> Void in
                let mp = unsafeBitCast(ptr, UnsafePointer<MIDIObjectAddRemoveNotification>.self)
                let m = mp.memory
                print("id \(m.messageID)")
                print("size \(m.messageSize)")
                print("child \(m.child)")
                print("child type \(m.childType)")
                print("parent \(m.parent)")
                print("parentType \(m.parentType)")
            }

            break
            
        case .MsgObjectRemoved:
            print("kMIDIMsgObjectRemoved")
            break
            
        case .MsgPropertyChanged:
            print("kMIDIMsgPropertyChanged")
            
            var mem = midiNotification.memory
            withUnsafePointer(&mem) { ptr -> Void in
                let mp = unsafeBitCast(ptr, UnsafePointer<MIDIObjectPropertyChangeNotification>.self)
                let m = mp.memory
                print("id \(m.messageID)")
                print("size \(m.messageSize)")
                print("object \(m.object)")
                print("objectType  \(m.objectType)")
                if m.propertyName.takeUnretainedValue() == kMIDIPropertyOffline {
                    var value = Int32(0)
                    let status = MIDIObjectGetIntegerProperty(m.object, kMIDIPropertyOffline, &value)
                    if status != noErr {
                        print("oops")
                    }
                    print("The offline property is \(value)")
                }

            }
            
            break
            
        case .MsgThruConnectionsChanged:
            print("MIDI thru connections changed.")
            break
            
        case .MsgSerialPortOwnerChanged:
            print("MIDI serial port owner changed.")
            break
            
        case .MsgIOError:
            print("MIDI I/O error.")
            //MIDIIOErrorNotification
            break
            
        }
        
    }
    
    
    func showError(status:OSStatus) {
        
        switch status {
            
        case OSStatus(kMIDIInvalidClient):
            print("invalid client")
            break
        case OSStatus(kMIDIInvalidPort):
            print("invalid port")
            break
        case OSStatus(kMIDIWrongEndpointType):
            print("invalid endpoint type")
            break
        case OSStatus(kMIDINoConnection):
            print("no connection")
            break
        case OSStatus(kMIDIUnknownEndpoint):
            print("unknown endpoint")
            break
            
        case OSStatus(kMIDIUnknownProperty):
            print("unknown property")
            break
        case OSStatus(kMIDIWrongPropertyType):
            print("wrong property type")
            break
        case OSStatus(kMIDINoCurrentSetup):
            print("no current setup")
            break
        case OSStatus(kMIDIMessageSendErr):
            print("message send")
            break
        case OSStatus(kMIDIServerStartErr):
            print("server start")
            break
        case OSStatus(kMIDISetupFormatErr):
            print("setup format")
            break
        case OSStatus(kMIDIWrongThread):
            print("wrong thread")
            break
        case OSStatus(kMIDIObjectNotFound):
            print("object not found")
            break
            
        case OSStatus(kMIDIIDNotUnique):
            print("not unique")
            break
            
        case OSStatus(kMIDINotPermitted):
            print("not permitted")
            break
            
        default:
            print("dunno \(status)")
        }
    }
    
        
    func enableNetwork() {
        let session = MIDINetworkSession.defaultSession()
        session.enabled = true
        session.connectionPolicy = .Anyone
        print("net session enabled \(MIDINetworkSession.defaultSession().enabled)")
    }
    
    func connectSourcesToInputPort() {
        var status = OSStatus(noErr)
        let sourceCount = MIDIGetNumberOfSources()
        print("source count \(sourceCount)")
        
        for srcIndex in 0 ..< sourceCount {
            let midiEndPoint = MIDIGetSource(srcIndex)
            status = MIDIPortConnectSource(inputPort,
                midiEndPoint,
                nil)
            if status == OSStatus(noErr) {
                print("yay connected endpoint to inputPort!")
            } else {
                print("oh crap!")
            }
        }
    }
    
    // Testing virtual destination
    
    
    
    func playWithMusicPlayer() {
        let sequence = createMusicSequence()
        self.musicPlayer = createMusicPlayer(sequence)
        playMusicPlayer()
    }
    
    func createMusicPlayer(musicSequence:MusicSequence) -> MusicPlayer {
        var musicPlayer = MusicPlayer()
        var status = OSStatus(noErr)
        
        status = NewMusicPlayer(&musicPlayer)
        if status != OSStatus(noErr) {
            print("bad status \(status) creating player")
        }
        
        status = MusicPlayerSetSequence(musicPlayer, musicSequence)
        if status != OSStatus(noErr) {
            print("setting sequence \(status)")
        }
        
        status = MusicPlayerPreroll(musicPlayer)
        if status != OSStatus(noErr) {
            print("prerolling player \(status)")
        }
        
        status = MusicSequenceSetMIDIEndpoint(musicSequence, self.destEndpointRef)
        if status != OSStatus(noErr) {
            print("error setting sequence endpoint \(status)")
        }
        
        return musicPlayer
    }
    
    func playMusicPlayer() {
        var status = OSStatus(noErr)
        var playing = Boolean(0)
        
        if let player = self.musicPlayer {
            status = MusicPlayerIsPlaying(player, &playing)
            if playing != 0 {
                print("music player is playing. stopping")
                status = MusicPlayerStop(player)
                if status != OSStatus(noErr) {
                    print("Error stopping \(status)")
                    return
                }
            } else {
                print("music player is not playing.")
            }
            
            status = MusicPlayerSetTime(player, 0)
            if status != OSStatus(noErr) {
                print("setting time \(status)")
                return
            }
            
            status = MusicPlayerStart(player)
            if status != OSStatus(noErr) {
                print("Error starting \(status)")
                return
            }
        }
    }
    
    
    func createMusicSequence() -> MusicSequence {
        
        var musicSequence = MusicSequence()
        var status = NewMusicSequence(&musicSequence)
        if status != OSStatus(noErr) {
            print("\(__LINE__) bad status \(status) creating sequence")
        }
        
        // just for fun, add a tempo track.
        var tempoTrack = MusicTrack()
        if MusicSequenceGetTempoTrack(musicSequence, &tempoTrack) != noErr {
            assert(tempoTrack != nil, "Cannot get tempo track")
        }
        //MusicTrackClear(tempoTrack, 0, 1)
        if MusicTrackNewExtendedTempoEvent(tempoTrack, 0.0, 128.0) != noErr {
            print("could not set tempo")
        }
        if MusicTrackNewExtendedTempoEvent(tempoTrack, 4.0, 256.0) != noErr {
            print("could not set tempo")
        }
        
        
        // add a track
        var track = MusicTrack()
        status = MusicSequenceNewTrack(musicSequence, &track)
        if status != OSStatus(noErr) {
            print("error creating track \(status)")
        }
        
        // bank select msb
        var chanmess = MIDIChannelMessage(status: 0xB0, data1: 0, data2: 0, reserved: 0)
        status = MusicTrackNewMIDIChannelEvent(track, 0, &chanmess)
        if status != OSStatus(noErr) {
            print("creating bank select event \(status)")
        }
        // bank select lsb
        chanmess = MIDIChannelMessage(status: 0xB0, data1: 32, data2: 0, reserved: 0)
        status = MusicTrackNewMIDIChannelEvent(track, 0, &chanmess)
        if status != OSStatus(noErr) {
            print("creating bank select event \(status)")
        }
        
        // program change. first data byte is the patch, the second data byte is unused for program change messages.
        chanmess = MIDIChannelMessage(status: 0xC0, data1: 0, data2: 0, reserved: 0)
        status = MusicTrackNewMIDIChannelEvent(track, 0, &chanmess)
        if status != OSStatus(noErr) {
            print("creating program change event \(status)")
        }
        
        // now make some notes and put them on the track
        var beat = MusicTimeStamp(0.0)
        for i:UInt8 in 60...72 {
            var mess = MIDINoteMessage(channel: 0,
                note: i,
                velocity: 64,
                releaseVelocity: 0,
                duration: 1.0 )
            status = MusicTrackNewMIDINoteEvent(track, beat, &mess)
            if status != OSStatus(noErr) {
                print("creating new midi note event \(status)")
            }
            beat++
        }
        
        // associate the AUGraph with the sequence.
        MusicSequenceSetAUGraph(musicSequence, self.processingGraph)
        
        // Let's see it
        CAShow(UnsafeMutablePointer<MusicSequence>(musicSequence))
        
        return musicSequence
    }
    
    func augraphSetup() {
        var status = OSStatus(noErr)
        status = NewAUGraph(&self.processingGraph)
        CheckError(status)
        
        // create the sampler
        
        //https://developer.apple.com/library/prerelease/ios/documentation/AudioUnit/Reference/AudioComponentServicesReference/index.html#//apple_ref/swift/struct/AudioComponentDescription
        
        var samplerNode = AUNode()
        var cd = AudioComponentDescription(
            componentType: OSType(kAudioUnitType_MusicDevice),
            componentSubType: OSType(kAudioUnitSubType_Sampler),
            componentManufacturer: OSType(kAudioUnitManufacturer_Apple),
            componentFlags: 0,
            componentFlagsMask: 0)
        status = AUGraphAddNode(self.processingGraph, &cd, &samplerNode)
        CheckError(status)
        
        // create the ionode
        var ioNode = AUNode()
        var ioUnitDescription = AudioComponentDescription(
            componentType: OSType(kAudioUnitType_Output),
            componentSubType: OSType(kAudioUnitSubType_RemoteIO),
            componentManufacturer: OSType(kAudioUnitManufacturer_Apple),
            componentFlags: 0,
            componentFlagsMask: 0)
        status = AUGraphAddNode(self.processingGraph, &ioUnitDescription, &ioNode)
        CheckError(status)
        
        // now do the wiring. The graph needs to be open before you call AUGraphNodeInfo
        status = AUGraphOpen(self.processingGraph)
        CheckError(status)
        
        status = AUGraphNodeInfo(self.processingGraph, samplerNode, nil, &self.samplerUnit)
        CheckError(status)
        
        var ioUnit  = AudioUnit()
        status = AUGraphNodeInfo(self.processingGraph, ioNode, nil, &ioUnit)
        CheckError(status)
        
        let ioUnitOutputElement = AudioUnitElement(0)
        let samplerOutputElement = AudioUnitElement(0)
        status = AUGraphConnectNodeInput(self.processingGraph,
            samplerNode, samplerOutputElement, // srcnode, inSourceOutputNumber
            ioNode, ioUnitOutputElement) // destnode, inDestInputNumber
        CheckError(status)
    }
    
    
    func graphStart() {
        //https://developer.apple.com/library/prerelease/ios/documentation/AudioToolbox/Reference/AUGraphServicesReference/index.html#//apple_ref/c/func/AUGraphIsInitialized
        
        var status = OSStatus(noErr)
        var outIsInitialized:Boolean = 0
        status = AUGraphIsInitialized(self.processingGraph, &outIsInitialized)
        print("isinit status is \(status)")
        print("bool is \(outIsInitialized)")
        if outIsInitialized == 0 {
            status = AUGraphInitialize(self.processingGraph)
            CheckError(status)
        }
        
        var isRunning = Boolean(0)
        AUGraphIsRunning(self.processingGraph, &isRunning)
        print("running bool is \(isRunning)")
        if isRunning == 0 {
            status = AUGraphStart(self.processingGraph)
            CheckError(status)
        }
        
    }
    
    func playNoteOn(channel:UInt32, noteNum:UInt32, velocity:UInt32)    {
        let noteCommand = UInt32(0x90 | channel)
        var status  = OSStatus(noErr)
        status = MusicDeviceMIDIEvent(self.samplerUnit, noteCommand, noteNum, velocity, 0)
        CheckError(status)
    }
    
    func playNoteOff(channel:UInt32, noteNum:UInt32)    {
        let noteCommand = UInt32(0x80 | channel)
        var status : OSStatus = OSStatus(noErr)
        status = MusicDeviceMIDIEvent(self.samplerUnit, noteCommand, noteNum, 0, 0)
        CheckError(status)
    }
    
    
    /// loads preset into self.samplerUnit
    func loadSF2Preset(preset:UInt8)  {
        
        // This is the MuseCore soundfont. Change it to the one you have.
        if let bankURL = NSBundle.mainBundle().URLForResource("GeneralUser GS MuseScore v1.442", withExtension: "sf2") {
            var instdata = AUSamplerInstrumentData(fileURL: Unmanaged.passUnretained(bankURL),
                instrumentType: UInt8(kInstrumentType_DLSPreset),
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB),
                presetID: preset)
            
            
            let status = AudioUnitSetProperty(
                self.samplerUnit,
                AudioUnitPropertyID(kAUSamplerProperty_LoadInstrument),
                AudioUnitScope(kAudioUnitScope_Global),
                0,
                &instdata,
                UInt32(sizeof(AUSamplerInstrumentData)))
            CheckError(status)
        }
    }
    
    
    
    /**
    Not as detailed as Adamson's CheckError, but adequate.
    For other projects you can uncomment the Core MIDI constants.
    */
    func CheckError(error:OSStatus) {
        if error == 0 {return}
        
        switch(Int(error)) {
        case kMIDIInvalidClient :
            print( "kMIDIInvalidClient ")
            
        case kMIDIInvalidPort :
            print( "kMIDIInvalidPort ")
            
        case kMIDIWrongEndpointType :
            print( "kMIDIWrongEndpointType")
            
        case kMIDINoConnection :
            print( "kMIDINoConnection ")
            
        case kMIDIUnknownEndpoint :
            print( "kMIDIUnknownEndpoint ")
            
        case kMIDIUnknownProperty :
            print( "kMIDIUnknownProperty ")
            
        case kMIDIWrongPropertyType :
            print( "kMIDIWrongPropertyType ")
            
        case kMIDINoCurrentSetup :
            print( "kMIDINoCurrentSetup ")
            
        case kMIDIMessageSendErr :
            print( "kMIDIMessageSendErr ")
            
        case kMIDIServerStartErr :
            print( "kMIDIServerStartErr ")
            
        case kMIDISetupFormatErr :
            print( "kMIDISetupFormatErr ")
            
        case kMIDIWrongThread :
            print( "kMIDIWrongThread ")
            
        case kMIDIObjectNotFound :
            print( "kMIDIObjectNotFound ")
            
        case kMIDIIDNotUnique :
            print( "kMIDIIDNotUnique ")
            
        default: print( "huh? \(error) ")
        }
        
        
        switch(error) {
            //AUGraph.h
        case kAUGraphErr_NodeNotFound:
            print("Error:kAUGraphErr_NodeNotFound \n")
            
        case kAUGraphErr_OutputNodeErr:
            print( "Error:kAUGraphErr_OutputNodeErr \n")
            
        case kAUGraphErr_InvalidConnection:
            print("Error:kAUGraphErr_InvalidConnection \n")
            
        case kAUGraphErr_CannotDoInCurrentContext:
            print( "Error:kAUGraphErr_CannotDoInCurrentContext \n")
            
        case kAUGraphErr_InvalidAudioUnit:
            print( "Error:kAUGraphErr_InvalidAudioUnit \n")
            
            // core audio
            
        case kAudio_UnimplementedError:
            print("kAudio_UnimplementedError")
        case kAudio_FileNotFoundError:
            print("kAudio_FileNotFoundError")
        case kAudio_FilePermissionError:
            print("kAudio_FilePermissionError")
        case kAudio_TooManyFilesOpenError:
            print("kAudio_TooManyFilesOpenError")
        case kAudio_BadFilePathError:
            print("kAudio_BadFilePathError")
        case kAudio_ParamError:
            print("kAudio_ParamError")
        case kAudio_MemFullError:
            print("kAudio_MemFullError")
            
            
            // AudioToolbox
            
        case kAudioToolboxErr_InvalidSequenceType :
            print( " kAudioToolboxErr_InvalidSequenceType ")
            
        case kAudioToolboxErr_TrackIndexError :
            print( " kAudioToolboxErr_TrackIndexError ")
            
        case kAudioToolboxErr_TrackNotFound :
            print( " kAudioToolboxErr_TrackNotFound ")
            
        case kAudioToolboxErr_EndOfTrack :
            print( " kAudioToolboxErr_EndOfTrack ")
            
        case kAudioToolboxErr_StartOfTrack :
            print( " kAudioToolboxErr_StartOfTrack ")
            
        case kAudioToolboxErr_IllegalTrackDestination :
            print( " kAudioToolboxErr_IllegalTrackDestination")
            
        case kAudioToolboxErr_NoSequence :
            print( " kAudioToolboxErr_NoSequence ")
            
        case kAudioToolboxErr_InvalidEventType :
            print( " kAudioToolboxErr_InvalidEventType")
            
        case kAudioToolboxErr_InvalidPlayerState :
            print( " kAudioToolboxErr_InvalidPlayerState")
            
            // AudioUnit
            
            
        case kAudioUnitErr_InvalidProperty :
            print( " kAudioUnitErr_InvalidProperty")
            
        case kAudioUnitErr_InvalidParameter :
            print( " kAudioUnitErr_InvalidParameter")
            
        case kAudioUnitErr_InvalidElement :
            print( " kAudioUnitErr_InvalidElement")
            
        case kAudioUnitErr_NoConnection :
            print( " kAudioUnitErr_NoConnection")
            
        case kAudioUnitErr_FailedInitialization :
            print( " kAudioUnitErr_FailedInitialization")
            
        case kAudioUnitErr_TooManyFramesToProcess :
            print( " kAudioUnitErr_TooManyFramesToProcess")
            
        case kAudioUnitErr_InvalidFile :
            print( " kAudioUnitErr_InvalidFile")
            
        case kAudioUnitErr_FormatNotSupported :
            print( " kAudioUnitErr_FormatNotSupported")
            
        case kAudioUnitErr_Uninitialized :
            print( " kAudioUnitErr_Uninitialized")
            
        case kAudioUnitErr_InvalidScope :
            print( " kAudioUnitErr_InvalidScope")
            
        case kAudioUnitErr_PropertyNotWritable :
            print( " kAudioUnitErr_PropertyNotWritable")
            
        case kAudioUnitErr_InvalidPropertyValue :
            print( " kAudioUnitErr_InvalidPropertyValue")
            
        case kAudioUnitErr_PropertyNotInUse :
            print( " kAudioUnitErr_PropertyNotInUse")
            
        case kAudioUnitErr_Initialized :
            print( " kAudioUnitErr_Initialized")
            
        case kAudioUnitErr_InvalidOfflineRender :
            print( " kAudioUnitErr_InvalidOfflineRender")
            
        case kAudioUnitErr_Unauthorized :
            print( " kAudioUnitErr_Unauthorized")
            
        default:
            print("huh?")
        }
    }
}



