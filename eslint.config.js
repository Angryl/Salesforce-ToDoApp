const { defineConfig } = require('eslint/config');
const lwcConfig = require('@salesforce/eslint-config-lwc/recommended');
const globals = require('globals');

module.exports = defineConfig([
    {
        files: ['**/lwc/**/*.js'],
        extends: [lwcConfig]
    },
    {
        files: ['**/lwc/**/*.test.js'],
        extends: [lwcConfig],
        rules: {
            '@lwc/lwc/no-unexpected-wire-adapter-usages': 'off'
        },
        languageOptions: {
            globals: {
                ...globals.node,
                ...globals.jest
            }
        }
    }
]);
