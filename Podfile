inhibit_all_warnings!

# Prefer the documented external folder structure:
#   ../DashSync/
# but also support this monorepo layout where DashSync lives at:
#   ../dashsync-iOS/
dashsync_path = File.expand_path('../DashSync', __dir__)
dashsync_path = File.expand_path('../dashsync-iOS', __dir__) unless File.exist?(File.join(dashsync_path, 'DashSync.podspec'))

swift_sdk_path = File.expand_path('../platform/packages/swift-sdk', __dir__)

target 'dashwallet' do
  platform :ios, '17.0'

  pod 'DAPI-GRPC', :path => dashsync_path
  pod 'DashSync', :path => dashsync_path
  pod 'SwiftDashSDK', :path => swift_sdk_path
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
  pod 'lottie-ios', '4.5.2'
  # Debugging purposes
  #  pod 'Reveal-SDK', :configurations => ['Debug']
  
end

target 'dashpay' do
  platform :ios, '17.0'

  pod 'DAPI-GRPC', :path => dashsync_path
  pod 'DashSync', :path => dashsync_path
  pod 'SwiftDashSDK', :path => swift_sdk_path
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
  pod 'lottie-ios', '4.5.2'

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
  platform :ios, '17.0'
  
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
      if target.platform_name == :ios
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      elsif target.platform_name == :watchos
        config.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = '4.0'
      end

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
  
  # Fix gRPC-Core template syntax issue with newer Xcode
  grpc_file = 'Pods/gRPC-Core/src/core/lib/promise/detail/basic_seq.h'
  if File.exist?(grpc_file)
    # Make file writable before modifying
    File.chmod(0644, grpc_file)
    text = File.read(grpc_file)
    new_contents = text.gsub(/Traits::template CallSeqFactory/, 'Traits::CallSeqFactory')
    File.write(grpc_file, new_contents)
  end

  # update info about current DashSync version
  # the command runs in the background after 1 sec, when `pod install` updates Podfile.lock
  system("(sleep 1; sh ./scripts/dashsync_version.sh) &")

end
