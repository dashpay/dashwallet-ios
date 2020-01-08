target 'dashwallet' do
  platform :ios, '11.0'
  
  pod 'DashSync', :path => '../DashSync/'
  pod 'DAPI-GRPC', :path => '../DashSync/'
  pod 'CloudInAppMessaging', '0.1.0'
  
  pod 'KVO-MVVM', '0.5.6'
  pod 'UIViewController-KeyboardAdditions', '1.2.1'
  pod 'MBProgressHUD', '1.1.0'
  pod 'MMSegmentSlider', :git => 'https://github.com/podkovyrin/MMSegmentSlider', :commit => '2d91366'

  # Debugging purposes
#  pod 'Reveal-SDK', :configurations => ['Debug']
  
  target 'DashWalletTests' do
    inherit! :search_paths
  end

  target 'DashWalletScreenshotsUITests' do
    inherit! :search_paths
  end

end

target 'TodayExtension' do
  platform :ios, '11.0'
  
  pod 'DSDynamicOptions', '0.1.1'

end

target 'WatchApp' do
  platform :watchos, '2.0'

end

target 'WatchApp Extension' do
  platform :watchos, '2.0'

end

post_install do |installer|
    installer.pods_project.targets.each do |target|
        # fixes warnings about unsupported Deployment Target in Xcode 10
        if ["BoringSSL-GRPC", "gRPC", "gRPC-Core", "gRPC-RxLibrary", "gRPC-ProtoRPC", "Protobuf", "DSJSONSchemaValidation", "!ProtoCompiler", "!ProtoCompiler-gRPCPlugin", "gRPC-gRPCCertificates"].include? target.name
            target.build_configurations.each do |config|
                config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '8.0'
            end
        end
        
        # temporary solution to work with gRPC-Core
        # see https://github.com/CocoaPods/CocoaPods/issues/8474
        if target.name == 'secp256k1_dash'
          target.build_configurations.each do |config|
              config.build_settings['HEADER_SEARCH_PATHS'] = '"${PODS_ROOT}/Headers/Private" "${PODS_ROOT}/Headers/Private/secp256k1_dash" "${PODS_ROOT}/Headers/Public" "${PODS_ROOT}/Headers/Public/secp256k1_dash"'
          end
        end
    end
    
    # update info about current DashSync version
    system("bash ./scripts/dashsync_version.sh")
end
