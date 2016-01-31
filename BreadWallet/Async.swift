//
//  Async.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 1/30/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

import Foundation

public struct AsyncError {
    var code: Int
    var message: String
}

public struct AsyncCallback<T> {
    let fn: (T) -> T?
}

public class AsyncResult<T> {
    private var successCallbacks: [AsyncCallback<T>] = [AsyncCallback<T>]()
    private var failureCallbacks: [AsyncCallback<AsyncError>] = [AsyncCallback<AsyncError>]()
    private var didCallbackSuccess: Bool = false
    private var didCallbackFailure: Bool = false
    
    private var successResult: T!
    private var errorResult: AsyncError!
    
    public var ID: String
    
    init() {
        ID = NSUUID().UUIDString
    }
    
    func success(cb: AsyncCallback<T>) -> AsyncResult<T> {
        objc_sync_enter(self)
        if didCallbackSuccess { // immediately call the callback if a result was already produced
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                objc_sync_enter(self)
                self.successResult = cb.fn(self.successResult)
                objc_sync_exit(self)
            })
        } else {
            successCallbacks.append(cb)
        }
        objc_sync_exit(self)
        return self
    }
    
    func failure(cb: AsyncCallback<AsyncError>) -> AsyncResult<T> {
        objc_sync_enter(self)
        if didCallbackFailure {
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                objc_sync_enter(self)
                self.errorResult = cb.fn(self.errorResult)
                objc_sync_exit(self)
            })
        } else {
            failureCallbacks.append(cb)
        }
        objc_sync_exit(self)
        return self
    }
    
    func succeed(result: T) -> AsyncResult<T> {
        objc_sync_enter(self)
        guard !didCallbackSuccess && !didCallbackFailure else {
            print("AsyncResult.succeed() error: callbacks already called. Result: \(result)")
            objc_sync_exit(self)
            return self
        }
        didCallbackSuccess = true
        objc_sync_exit(self)
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            objc_sync_enter(self)
            self.successResult = result
            for cb in self.successCallbacks {
                if let newResult = cb.fn(self.successResult) {
                    self.successResult = newResult
                } else {
                    break // returning nil terminates the callback chain
                }
            }
            objc_sync_exit(self)
        }
        return self
    }
    
    func error(code: Int, message: String) -> AsyncResult<T> {
        objc_sync_enter(self)
        guard !didCallbackSuccess && !didCallbackFailure else {
            print("AsyncResult.error() error: callbacks already called. Error: \(code), \(message)")
            objc_sync_exit(self)
            return self
        }
        didCallbackFailure = true
        objc_sync_exit(self)
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            objc_sync_enter(self)
            self.errorResult = AsyncError(code: code, message: message)
            for cb in self.failureCallbacks {
                if let newResult = cb.fn(self.errorResult) {
                    self.errorResult = newResult
                } else {
                    break // returning nil terminates the callback chain
                }
            }
            objc_sync_exit(self)
        }
        return self
    }
    
    func error(e: AsyncError) -> AsyncResult<T> {
        return error(e.code, message: e.message)
    }
}
