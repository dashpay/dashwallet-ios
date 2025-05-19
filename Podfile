inhibit_all_warnings!

target 'dashwallet' do
  platform :ios, '14.0'
  
  pod 'DashSync', :path => '../DashSync/'
  pod 'SQLite.swift', '~> 0.15.3'
  pod 'SQLiteMigrationManager.swift', '0.8.3'
  pod 'CloudInAppMessaging', '0.1.0'
  pod 'FirebaseStorage', '8.15.0'
  pod 'Firebase/DynamicLinks'
  pod 'SSZipArchive'
  pod 'KVO-MVVM', '0.5.6'
  pod 'UIViewController-KeyboardAdditions', '1.2.1'
  pod 'MBProgressHUD', '1.1.0'
  pod 'MMSegmentSlider', :git => 'https://github.com/podkovyrin/MMSegmentSlider', :commit => '2d91366'
  pod 'CocoaImageHashing', :git => 'https://github.com/ameingast/cocoaimagehashing.git', :commit => 'ad01eee'
  pod 'SDWebImage', '5.21.0', :modular_headers => true
  pod 'SDWebImageSwiftUI', '3.1.3', :modular_headers => true
  pod 'Moya', '~> 15.0'
  pod 'SwiftJWT', '3.6.200'
  # Debugging purposes
  #  pod 'Reveal-SDK', :configurations => ['Debug']
  
end

target 'dashpay' do
  platform :ios, '14.0'
  
  pod 'DashSync', :path => '../DashSync/'
  pod 'SQLite.swift', '~> 0.15.3'
  pod 'SQLiteMigrationManager.swift', '0.8.3'
  pod 'CloudInAppMessaging', '0.1.0'
  pod 'FirebaseStorage', '8.15.0'
  pod 'Firebase/DynamicLinks'
  pod 'SSZipArchive'
  pod 'KVO-MVVM', '0.5.6'
  pod 'UIViewController-KeyboardAdditions', '1.2.1'
  pod 'MBProgressHUD', '1.1.0'
  pod 'MMSegmentSlider', :git => 'https://github.com/podkovyrin/MMSegmentSlider', :commit => '2d91366'
  pod 'CocoaImageHashing', :git => 'https://github.com/ameingast/cocoaimagehashing.git', :commit => 'ad01eee'
  pod 'SDWebImage', '5.21.0', :modular_headers => true
  pod 'SDWebImageSwiftUI', '3.1.3', :modular_headers => true
  pod 'Moya', '~> 15.0'
  pod 'SwiftJWT', '3.6.200'
  pod 'TOCropViewController', '2.6.1'

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
  platform :ios, '13.0'
  
  pod 'DSDynamicOptions', '0.1.2'

end

target 'WatchApp' do
  platform :watchos, '4.0'

end

target 'WatchApp Extension' do
  platform :watchos, '4.0'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|

    # fixes warnings about unsupported Deployment Target in Xcode
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'

    end

    # Ensure the GCC_WARN_INHIBIT_ALL_WARNINGS flag is removed for BoringSSL-GRPC and BoringSSL-GRPC-iOS
    if ['BoringSSL-GRPC', 'BoringSSL-GRPC-iOS'].include? target.name
      target.source_build_phase.files.each do |file|
        if file.settings && file.settings['COMPILER_FLAGS']
          flags = file.settings['COMPILER_FLAGS'].split
          flags.reject! { |flag| flag == '-GCC_WARN_INHIBIT_ALL_WARNINGS' }
          file.settings['COMPILER_FLAGS'] = flags.join(' ')
        end
      end
    end

    # temporary solution to work with gRPC-Core
    # see https://github.com/CocoaPods/CocoaPods/issues/8474
    if target.name == 'secp256k1_dash'
      target.build_configurations.each do |config|
        config.build_settings['HEADER_SEARCH_PATHS'] = '"${PODS_ROOT}/Headers/Private" "${PODS_ROOT}/Headers/Private/secp256k1_dash" "${PODS_ROOT}/Headers/Public" "${PODS_ROOT}/Headers/Public/secp256k1_dash" "${PODS_ROOT}/secp256k1_dash"'
      end
    end
  end

  # update info about current DashSync version
  # the command runs in the background after 1 sec, when `pod install` updates Podfile.lock
  system("(sleep 1; sh ./scripts/dashsync_version.sh) &")

end
