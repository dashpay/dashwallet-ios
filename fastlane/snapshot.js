#import "SnapshotHelper.js"

var target = UIATarget.localTarget();
var app = target.frontMostApp();
var window = app.mainWindow();

target.delay(0.5);
captureLocalizedScreenshot('1');

target.tap({x:100, y:50});
target.delay(0.5);
captureLocalizedScreenshot('0');

target.tap({x:100, y:50});
target.delay(0.5);
captureLocalizedScreenshot('2');

window.pageIndicators()[0].tap();
target.delay(0.5);
captureLocalizedScreenshot('3');

app.navigationBar().buttons()[0].tap();
target.delay(0.5);
captureLocalizedScreenshot('4');
