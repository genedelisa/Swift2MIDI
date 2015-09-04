//
//  ViewController.swift
//  Swift2MIDI
//
//  Created by Gene De Lisa on 6/9/15.
//  Copyright © 2015 Gene De Lisa. All rights reserved.
//

import UIKit
import CoreMIDI

class ViewController: UIViewController {

    @IBOutlet var textView: UITextView!
    
    let manager = MIDIManager.sharedInstance
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    
        // this will use the read block that writes to the textview
        manager.initMIDI(reader: MyMIDIReadBlock)
        
        // this will use the default readblock (and notificationblock) in the manager which prints to stdout
//        manager.initMIDI()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    @IBAction func playSequence(sender: UIButton) {
        manager.playWithMusicPlayer()
    }

    func MyMIDIReadBlock(packetList: UnsafePointer<MIDIPacketList>, srcConnRefCon: UnsafeMutablePointer<Void>) -> Void {

        let packets = packetList.memory
        let packet:MIDIPacket = packets.packet
        var ap = UnsafeMutablePointer<MIDIPacket>.alloc(1)
        ap.initialize(packet)
        
        for _ in 0 ..< packets.numPackets {
            let p = ap.memory
            handle(p)
            ap = MIDIPacketNext(ap)
        }
        
    }

    func handle(packet:MIDIPacket) {

        let status = packet.data.0
        let d1 = packet.data.1
        let d2 = packet.data.2
        let rawStatus = status & 0xF0 // without channel

        
        if status < 0xF0 {
            
            let channel = status & 0x0F
            
            switch rawStatus {
                
            case 0x80:
                
                dispatch_async(dispatch_get_main_queue(), {
                    self.textView.text = self.textView.text.stringByAppendingString("Note off. Channel \(channel) note \(d1) velocity \(d2)\n")
                    self.manager.playNoteOff(UInt32(channel), noteNum: UInt32(d1))

                })
                
            case 0x90:
                
                dispatch_async(dispatch_get_main_queue(), {
                    self.textView.text = self.textView.text.stringByAppendingString("Note on. Channel \(channel) note \(d1) velocity \(d2)\n")
                    self.manager.playNoteOn(UInt32(channel), noteNum:UInt32(d1), velocity: UInt32(d2))

                })
                
            case 0xA0:
                print("Polyphonic Key Pressure (Aftertouch). Channel \(channel) note \(d1) pressure \(d2)", terminator: "")
                dispatch_async(dispatch_get_main_queue(), {
                    self.textView.text = self.textView.text.stringByAppendingString("Note on. Channel \(channel) note \(d1) velocity \(d2)\n")
                })
            case 0xB0:
                
                dispatch_async(dispatch_get_main_queue(), {
                    self.textView.text = self.textView.text.stringByAppendingString("Control Change. Channel \(channel) controller \(d1) value \(d2)\n")
                })
                
            case 0xC0:
                dispatch_async(dispatch_get_main_queue(), {
                    self.textView.text = self.textView.text.stringByAppendingString("Program Change. Channel \(channel) program \(d1)\n")
                })
            case 0xD0:
                
                dispatch_async(dispatch_get_main_queue(), {
                    self.textView.text = self.textView.text.stringByAppendingString("Channel Pressure (Aftertouch). Channel \(channel) pressure \(d1)\n")
                    
                })
            case 0xE0:
                
                dispatch_async(dispatch_get_main_queue(), {
                    self.textView.text = self.textView.text.stringByAppendingString("Pitch Bend Change. Channel \(channel) lsb \(d1) msb \(d2)\n")
                    
                })
            case 0xFE:
                print("active sensing", terminator: "")
                dispatch_async(dispatch_get_main_queue(), {
                    self.textView.text = self.textView.text.stringByAppendingString("\n")
                })
                
            default:
                let hex = String(status, radix: 16, uppercase: true)
                print("Unhandled message \(status) \(hex)", terminator: "")
            }
        }
        
        if status >= 0xF0 {
            switch status {
            case 0xF0:
                print("Sysex", terminator: "")
            case 0xF1:
                print("MIDI Time Code", terminator: "")
            case 0xF2:
                print("Song Position Pointer", terminator: "")
            case 0xF3:
                print("Song Select", terminator: "")
            case 0xF4:
                print("Reserved", terminator: "")
            case 0xF5:
                print("Reserved", terminator: "")
            case 0xF6:
                print("Tune request", terminator: "")
            case 0xF7:
                print("End of SysEx", terminator: "")
            case 0xF8:
                print("Timing clock", terminator: "")
            case 0xF9:
                print("Reserved", terminator: "")
            case 0xFA:
                print("Start", terminator: "")
            case 0xFB:
                print("Continue", terminator: "")
            case 0xFC:
                print("Stop", terminator: "")
            case 0xFD:
                print("Start", terminator: "")
                
            default: break
                
            }
        }
        
        // make the textview scroll to bottom
        dispatch_async(dispatch_get_main_queue(), {
            let len = self.textView.text.characters.count
            if len > 0 {
                let bottom = NSMakeRange(len - 1, 1)
                self.textView.scrollRangeToVisible(bottom)
            }
        })
    }

}

