#!/usr/bin/env node

/**
 * Before Install Hook
 * Runs before the Hot Updates plugin is installed
 */

module.exports = function(context) {
    console.log('Installing Cordova Hot Updates Plugin...');
    console.log('Please ensure your project has SSZipArchive available via CocoaPods.');
    console.log('If you don\'t have a Podfile, one will be created automatically.');

    return Promise.resolve();
};