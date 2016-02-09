//
//  BRTar.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/8/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation


enum BRTarError: ErrorType {
    case Unknown
    case FileDoesntExist
}

enum BRTarType {
    case File
    case Directory
    case NullBlock
    case HeaderBlock
    case Unsupported
    case Invalid
    
    init(fromData: NSData) {
        let byte = UnsafePointer<CChar>(fromData.bytes)[0]
        switch byte {
        case CChar(48): // "0"
            self = File
        case CChar(53): // "5"
            self = Directory
        case CChar(0):
            self = NullBlock
        case CChar(120): // "x"
            self = HeaderBlock
        case CChar(49), CChar(50), CChar(51), CChar(52), CChar(53), CChar(54), CChar(55), CChar(103):
            // "1, 2, 3, 4, 5, 6, 7, g"
            self = Unsupported
        default:
            BRTar.log("invalid block type: \(byte)")
            self = Invalid
        }
    }
}

class BRTar {
    static let tarBlockSize: UInt64 = 512
    static let tarTypePosition: UInt64 = 156
    static let tarNamePosition: UInt64 = 0
    static let tarNameSize: UInt64 = 100
    static let tarSizePosition: UInt64 = 124
    static let tarSizeSize: UInt64 = 12
    static let tarMaxBlockLoadInMemory: UInt64 = 100
    static let tarLogEnabled: Bool = false
    
    static func createFilesAndDirectoriesAtPath(path: String, withTarPath tarPath: String) throws {
        let fm = NSFileManager.defaultManager()
        if !fm.fileExistsAtPath(tarPath) {
            log("tar file \(tarPath) does not exist")
            throw BRTarError.FileDoesntExist
        }
        let attrs = try fm.attributesOfItemAtPath(tarPath)
        guard let tarFh = NSFileHandle(forReadingAtPath: tarPath) else {
            log("could not open tar file for reading")
            throw BRTarError.Unknown
        }
        var loc: UInt64 = 0
        guard let size = attrs[NSFileSize]?.unsignedLongLongValue else {
            log("could not read tar file size")
            throw BRTarError.Unknown
        }
        
        while loc < size {
            var blockCount: UInt64 = 1
            let tarType = readTypeAtLocation(loc, fromHandle: tarFh)
            switch tarType {
            case .File:
                // read name
                let name = try readNameAtLocation(loc, fromHandle: tarFh)
                log("got file name from tar \(name)")
                let newFilePath = (path as NSString).stringByAppendingPathComponent(name)
                log("will write to \(newFilePath)")
                var size = readSizeAtLocation(loc, fromHandle: tarFh)
                log("its size is \(size)")
                
                if fm.fileExistsAtPath(newFilePath) {
                    try fm.removeItemAtPath(newFilePath)
                }
                if size == 0 {
                    // empty file
                    try "" .writeToFile(newFilePath, atomically: true, encoding: NSUTF8StringEncoding)
                    break
                }
                blockCount += (size - 1) / tarBlockSize + 1
                // write file
                fm.createFileAtPath(newFilePath, contents: nil, attributes: nil)
                guard let destFh = NSFileHandle(forWritingAtPath: newFilePath) else {
                    log("unable to open destination file for writing")
                    throw BRTarError.Unknown
                }
                tarFh.seekToFileOffset(loc + tarBlockSize)
                let maxSize = tarMaxBlockLoadInMemory * tarBlockSize
                while size > maxSize {
                    autoreleasepool({ () -> () in
                        destFh.writeData(tarFh.readDataOfLength(Int(maxSize)))
                        size -= maxSize
                    })
                }
                destFh.writeData(tarFh.readDataOfLength(Int(size)))
                destFh.closeFile()
                log("success writing file")
                break
            case .Directory:
                let name = try readNameAtLocation(loc, fromHandle: tarFh)
                log("got new directory name \(name)")
                let dirPath = (path as NSString).stringByAppendingPathComponent(name)
                log("will create directory at \(dirPath)")
                
                if fm.fileExistsAtPath(dirPath) {
                    try fm.removeItemAtPath(dirPath) // will automatically recursively remove directories if exists
                }
                
                try fm.createDirectoryAtPath(dirPath, withIntermediateDirectories: true, attributes: nil)
                log("success creating directory")
                break
            case .NullBlock:
                break
            case .HeaderBlock:
                blockCount++
                break
            case .Unsupported:
                let size = readSizeAtLocation(loc, fromHandle: tarFh)
                blockCount += size / tarBlockSize
                break
            case .Invalid:
                log("Invalid block encountered")
                throw BRTarError.Unknown
            }
            loc += blockCount * tarBlockSize
            log("new location \(loc)")
        }
    }
    
    static private func readTypeAtLocation(location: UInt64, fromHandle handle: NSFileHandle) -> BRTarType {
        log("reading type at location \(location)")
        handle.seekToFileOffset(location + tarTypePosition)
        let typeDat = handle.readDataOfLength(1)
        let ret = BRTarType(fromData: typeDat)
        log("type: \(ret)")
        return ret
    }
    
    static private func readNameAtLocation(location: UInt64, fromHandle handle: NSFileHandle) throws -> String {
        handle.seekToFileOffset(location + tarNamePosition)
        guard let ret = NSString(data: handle.readDataOfLength(Int(tarNameSize)), encoding: NSASCIIStringEncoding)
            else {
                log("unable to read name")
                throw BRTarError.Unknown
        }
        return ret as String
    }
    
    static private func readSizeAtLocation(location: UInt64, fromHandle handle: NSFileHandle) -> UInt64 {
        handle.seekToFileOffset(location + tarSizePosition)
        let sizeDat = handle.readDataOfLength(Int(tarSizeSize))
        let octal = NSString(data: sizeDat, encoding: NSASCIIStringEncoding)!
        log("size octal: \(octal)")
        let dec = strtoll(octal.UTF8String, nil, 8)
        log("size decimal: \(dec)")
        return UInt64(dec)
    }
    
    static private func log(string: String) {
        if tarLogEnabled {
            print("[BRTar] \(string)")
        }
    }
}
