//
//  BRBSPatch.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 2/8/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation


enum BRBSPatchError: ErrorType {
    case Unknown
    case CorruptPatch
    case PatchFileDoesntExist
    case OldFileDoesntExist
}


class BRBSPatch {
    static let patchLogEnabled = true
    
    static func patch(oldFilePath: String, newFilePath: String, patchFilePath: String) throws -> UnsafeMutablePointer<CUnsignedChar> {
        func offtin(b: UnsafePointer<CUnsignedChar>) -> off_t {
            var y = off_t(b[0])
            y |= off_t(b[1]) << 8
            y |= off_t(b[2]) << 16
            y |= off_t(b[3]) << 24
            y |= off_t(b[4]) << 32
            y |= off_t(b[5]) << 40
            y |= off_t(b[6]) << 48
            y |= off_t(b[7] & 0x7f) << 56
            if Int(b[7]) & 0x80 != 0 {
                y = -y
            }
            return y
        }
        let patchFilePathBytes = UnsafePointer<Int8>((patchFilePath as NSString).UTF8String)
        let r = UnsafePointer<Int8>(("r" as NSString).UTF8String)
        
        // open patch file
        guard let f = NSFileHandle(forReadingAtPath: patchFilePath) else {
            log("unable to open file for reading at path \(patchFilePath)")
            throw BRBSPatchError.PatchFileDoesntExist
        }
        
        // read header
        let headerData = f.readDataOfLength(32)
        let header = UnsafePointer<CUnsignedChar>(headerData.bytes)
        if headerData.length != 32 {
            log("incorrect header read length \(headerData.length)")
            throw BRBSPatchError.CorruptPatch
        }
        
        // check for appropriate magic
        let magicData = headerData.subdataWithRange(NSMakeRange(0, 8))
        if let magic = NSString(data: magicData, encoding: NSASCIIStringEncoding)
            where magic != "BSDIFF40" {
                log("incorrect magic: \(magic)")
                throw BRBSPatchError.CorruptPatch
        }
        
        // read lengths from header
        let bzCrtlLen = offtin(header + 8)
        let bzDataLen = offtin(header + 16)
        let newSize = offtin(header + 24)
        
        if bzCrtlLen < 0 || bzDataLen < 0 || newSize < 0 {
            log("incorrect header data: crtlLen: \(bzCrtlLen) dataLen: \(bzDataLen) newSize: \(newSize)")
            throw BRBSPatchError.CorruptPatch
        }
        
        // close patch file and re-open it with bzip2 at the right positions
        f.closeFile()
        
        let cpf = fopen(patchFilePathBytes, r)
        if cpf == nil {
            let s = String.fromCString(strerror(errno))
            let ff = String.fromCString(patchFilePathBytes)
            log("unable to open patch file c: \(s) \(ff)")
            throw BRBSPatchError.Unknown
        }
        let cpfseek = fseeko(cpf, 32, SEEK_SET)
        if cpfseek != 0 {
            log("unable to seek patch file c: \(cpfseek)")
            throw BRBSPatchError.Unknown
        }
        let cbz2err = UnsafeMutablePointer<Int32>.alloc(1)
        let cpfbz2 = BZ2_bzReadOpen(cbz2err, cpf, 0, 0, nil, 0)
        if cpfbz2 == nil {
            log("unable to bzopen patch file c: \(cbz2err)")
            throw BRBSPatchError.Unknown
        }
        let dpf = fopen(patchFilePathBytes, r)
        if dpf == nil {
            log("unable to open patch file d")
            throw BRBSPatchError.Unknown
        }
        let dpfseek = fseeko(dpf, 32 + bzCrtlLen, SEEK_SET)
        if dpfseek != 0 {
            log("unable to seek patch file d: \(dpfseek)")
            throw BRBSPatchError.Unknown
        }
        let dbz2err = UnsafeMutablePointer<Int32>.alloc(1)
        let dpfbz2 = BZ2_bzReadOpen(dbz2err, dpf, 0, 0, nil, 0)
        if dpfbz2 == nil {
            log("unable to bzopen patch file d: \(dbz2err)")
            throw BRBSPatchError.Unknown
        }
        let epf = fopen(patchFilePathBytes, r)
        if epf == nil {
            log("unable to open patch file e")
            throw BRBSPatchError.Unknown
        }
        let epfseek = fseeko(epf, 32 + bzCrtlLen + bzDataLen, SEEK_SET)
        if epfseek != 0 {
            log("unable to seek patch file e: \(epfseek)")
            throw BRBSPatchError.Unknown
        }
        let ebz2err = UnsafeMutablePointer<Int32>.alloc(1)
        let epfbz2 = BZ2_bzReadOpen(ebz2err, epf, 0, 0, nil, 0)
        if epfbz2 == nil {
            log("unable to bzopen patch file e: \(ebz2err)")
            throw BRBSPatchError.Unknown
        }
        
        guard let oldData = NSData(contentsOfFile: oldFilePath) else {
            log("unable to read old file path")
            throw BRBSPatchError.Unknown
        }
        let old = UnsafePointer<CUnsignedChar>(oldData.bytes)
        let oldSize = off_t(oldData.length)
        var oldPos: off_t = 0, newPos: off_t = 0
        let new = UnsafeMutablePointer<CUnsignedChar>(malloc(Int(newSize) + 1))
        let buf = UnsafeMutablePointer<CUnsignedChar>(malloc(8))
        var crtl = Array<off_t>(count: 3, repeatedValue: 0)
        while newPos < newSize {
            // read control data
            for i in 0...2 {
                let lenread = BZ2_bzRead(cbz2err, cpfbz2, buf, 8)
                if (lenread < 8) || ((cbz2err.memory != BZ_OK) && (cbz2err.memory != BZ_STREAM_END)) {
                    log("unable to read control data \(lenread) \(cbz2err.memory)")
                    throw BRBSPatchError.CorruptPatch
                }
                crtl[i] = offtin(UnsafePointer<CUnsignedChar>(buf))
            }
            // sanity check
            if (newPos + crtl[0]) > newSize {
                log("incorrect size of crtl[0]")
                throw BRBSPatchError.CorruptPatch
            }
            
            // read diff string
            let dlenread = BZ2_bzRead(dbz2err, dpfbz2, new + Int(newPos), Int32(crtl[0]))
            if (dlenread < Int32(crtl[0])) || ((dbz2err.memory != BZ_OK) && (dbz2err.memory != BZ_STREAM_END)) {
                log("unable to read diff string \(dlenread) \(dbz2err.memory)")
                throw BRBSPatchError.CorruptPatch
            }
            
            // add old data to diff string
            if crtl[0] > 0 {
                for i in 0...(Int(crtl[0]) - 1) {
                    if (oldPos + i >= 0) && (oldPos + i < oldSize) {
                        let np = Int(newPos) + i, op = Int(oldPos) + i
                        new[np] = new[np] &+ old[op]
                    }
                }
            }
            
            // adjust pointers
            newPos += crtl[0]
            oldPos += crtl[0]
            
            // sanity check
            if (newPos + crtl[1]) > newSize {
                log("incorrect size of crtl[1]")
                throw BRBSPatchError.CorruptPatch
            }
            
            // read extra string
            let elenread = BZ2_bzRead(ebz2err, epfbz2, new + Int(newPos), Int32(crtl[1]))
            if (elenread < Int32(crtl[1])) || ((ebz2err.memory != BZ_OK) && (ebz2err.memory != BZ_STREAM_END)) {
                log("unable to read extra string \(elenread) \(ebz2err.memory)")
                throw BRBSPatchError.CorruptPatch
            }
            
            // adjust pointers
            newPos += crtl[1]
            oldPos += crtl[2]
        }
        
        // clean up bz2 reads
        BZ2_bzReadClose(cbz2err, cpfbz2)
        BZ2_bzReadClose(dbz2err, dpfbz2)
        BZ2_bzReadClose(ebz2err, epfbz2)
        
        if (fclose(cpf) != 0) || (fclose(dpf) != 0) || (fclose(epf) != 0) {
            log("unable to close bzip file handles")
            throw BRBSPatchError.Unknown
        }
        
        // write out new file
        let fm = NSFileManager.defaultManager()
        if fm.fileExistsAtPath(newFilePath) {
            try fm.removeItemAtPath(newFilePath)
        }
        let newData = NSData(bytes: new, length: Int(newSize))
        try newData.writeToFile(newFilePath, options: .DataWritingAtomic)
        return new
    }
    
    static private func log(string: String) {
        if patchLogEnabled {
            print("[BRBSPatch] \(string)")
        }
    }
}
