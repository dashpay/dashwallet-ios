inhibit_all_warnings!

def common_pods

  platform :ios, '14.0'

  pod 'DashSync', :path => '../DashSync/'
#  pod 'DashSharedCore', :path => '../dash-shared-core/'
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
  pod 'SDWebImage', '5.21.0'
  pod 'Moya', '~> 15.0'
  pod 'SwiftJWT', '3.6.200'
  # Debugging purposes
  #  pod 'Reveal-SDK', :configurations => ['Debug']

end

target 'dashwallet' do
  common_pods
end

target 'dashpay' do
  common_pods
  pod 'TOCropViewController', '2.6.1'

  target 'DashWalletTests' do
    inherit! :search_paths
  end

  target 'DashWalletScreenshotsUITests' do
    inherit! :search_paths
  end

end


target 'TodayExtension' do
  platform :ios, '14.0'
  
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
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << 'DASHCORE_QUORUM_VALIDATION=1'
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << 'DPP_STATE_TRANSITIONS=1'
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << 'PLATFORM_VALUE_STD=1'
    end
  end
  # update info about current DashSync version
  # the command runs in the background after 1 sec, when `pod install` updates Podfile.lock
  system("(sleep 1; sh ./scripts/dashsync_version.sh)")
end
