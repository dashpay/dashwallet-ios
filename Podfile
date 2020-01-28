target 'dashwallet' do
  platform :ios, '11.0'
  
  pod 'DashSync', :git => 'https://github.com/dashevo/dashsync-iOS/', :commit => 'd735a86'
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
  
  pod 'DSDynamicOptions', '0.1.0'

end

target 'WatchApp' do
  platform :watchos, '2.0'

end

target 'WatchApp Extension' do
  platform :watchos, '2.0'

end

post_install do |installer|
    # update info about current DashSync version
    # the command runs in the background after 1 sec, when `pod install` updates Podfile.lock
    system("(sleep 1; sh ./scripts/dashsync_version.sh) &")
end
