#!/usr/bin/env node

/**
 * After Install Hook
 * Runs after the Hot Updates plugin is installed
 */

module.exports = function(context) {
    console.log('Cordova Hot Updates Plugin installed successfully!');
    console.log('');
    console.log('Configuration:');
    console.log('Add these preferences to your config.xml:');
    console.log('');
    console.log('<preference name="hot_updates_server_url" value="https://your-server.com/api/updates" />');
    console.log('<preference name="hot_updates_check_interval" value="300000" />');
    console.log('');
    console.log('Next steps:');
    console.log('1. Configure your update server URL in config.xml');
    console.log('2. Run "pod install" in your iOS platform directory');
    console.log('3. Build and test your application');
    console.log('');
    console.log('Documentation: https://github.com/vladimirDarksy/Cordova_hot_update');

    return Promise.resolve();
};