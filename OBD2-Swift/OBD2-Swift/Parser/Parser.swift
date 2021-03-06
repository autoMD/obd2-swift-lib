//
//  Parser.swift
//  OBD2Swift
//
//  Created by Max Vitruk on 25/05/2017.
//  Copyright © 2017 Lemberg. All rights reserved.
//

import Foundation

class Parser {
  static let string = StringParser()
  static let package = PackageReader()
  
  class StringParser {
    let kResponseFinishedCode : UInt8	=	0x3E
    
    func isReadComplete(_ buf : [UInt8]) -> Bool {
      return buf.last == kResponseFinishedCode
    }
    
    func isOK(_ str : String) -> Bool{
      return str.contains("OK")
    }
    
    func isError(_ str : String)	-> Bool	{
      return str.contains("?")
    }
    
    func isNoData(_ str : String)	-> Bool	{
      return str.contains("NO DATA")
    }
    
    func isSerching(_ str : String)	-> Bool	{
      return str.contains("SEARCHING...")
    }
    
    func isAuto(_ str : String) -> Bool {
      return str.hasPrefix("AUTO")
    }
    
    func isDataResponse(_ str : String)	-> Bool	{
      let unwrapStr = str.characters.first ?? Character.init("")
      let str = String(describing: unwrapStr)
      let isDigit = Int(str) != nil
      return isDigit || isSerching(str)
    }
    
    func isATResponse(_ str : [Int8])	-> Bool	{
      guard let char = str.first else {return false}
      guard let int32 = Int32.init(exactly: char) else {return false}
      return isalpha(int32) == 0
    }
    
    func getProtocol(fro index : Int8) -> ScanToolProtocol {
      let i = Int(index)
      return elm_protocol_map[i]
    }
    
    func protocolName(`protocol` : ScanToolProtocol) -> String {
      switch `protocol` {
      case .ISO9141Keywords0808:
        return "ISO 9141-2 Keywords 0808"
      case .ISO9141Keywords9494:
        return "ISO 9141-2 Keywords 9494"
      case .KWP2000FastInit:
        return "KWP2000 Fast Init"
      case .KWP2000SlowInit:
        return "KWP2000 Slow Init"
      case .J1850PWM:
        return "J1850 PWM"
      case .J1850VPW:
        return "J1850 VPW"
      case .CAN11bit250KB:
        return "CAN 11-Bit 250Kbps"
      case .CAN11bit500KB:
        return "CAN 11-Bit 500Kbps"
      case .CAN29bit250KB:
        return "CAN 29-Bit 250Kbps"
      case .CAN29bit500KB:
        return "CAN 29-Bit 500Kbps"
      case .none:
        return"Unknown Protocol"
      }
    }
  }
  
  //Parsing command response
  class PackageReader {
    func read(package : Package) -> [ScanToolResponse] {
      return parseResponse(package: package)
    }
    
    private func optimize(package : inout Package){
      while package.buffer.last == 0x00 || package.buffer.last == 0x20 {
        package.buffer.removeLast()
      }
    }
    
    private func parseResponse(package p : Package) -> [ScanToolResponse] {
      var package = p
      optimize(package: &package)
      
      var responseArray = [ScanToolResponse]()
      
      /*
       TODO:
       
       41 00 BF 9F F9 91 41 00 90 18 80 00
       
       Deal with cases where the ELM327 does not properly insert a CR in between
       a multi-ECU response packet (real-world example above - Mode $01 PID $00).
       
       Need to split on modulo 6 boundary and check to ensure total packet length
       is a multiple of 6.  If not, we'll have to discard.
       
       */
      
      if !package.isError && package.isData {
        let responseComponents = package.strigDescriptor.components(separatedBy: "\r")
        
        for resp in responseComponents {
          if Parser.string.isSerching(resp) {
            // A common reply if PID search occuring for the first time
            // at this drive cycle
            break;
          }
          
          var decodeBufLength = 0
          var decodeBuf = [UInt8]()
          
          // For each response data string, decode into an integer array for
          // easier processing
          
          let chunks = resp.components(separatedBy: " ")
          
          for c in chunks {
            let value = Int(strtoul(c, nil, 16))
            decodeBuf.append(UInt8(value))
            decodeBufLength += 1
          }
          
          let obj = decode(data: decodeBuf, length: decodeBufLength)
          responseArray.append(obj)
        }

      }
      
      return responseArray
    }
    
    func decode(data : [UInt8], length : Int) -> ScanToolResponse {
      let resp = ScanToolResponse()
      var dataIndex = 0
      
      resp.scanToolName		  = "ELM327";
//      resp.`protocol`       = `protocol`
      resp.responseData			= Data.init(bytes: data, count: length)
      resp.mode             = (data[dataIndex] ^ 0x40)
      dataIndex            += 1
      
      if resp.mode == ScanToolMode.RequestCurrentPowertrainDiagnosticData.rawValue {
        resp.pid			= data[dataIndex]
        dataIndex += 1
      }
      
      if(length > 2) {
        resp.data	= Data.init(bytes: [data[dataIndex]], count: length-dataIndex)
      }
      
      return resp
    }
  }
}
