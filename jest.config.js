const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...jestConfig.moduleNameMapper,
    "^lightning/mobileCapabilities$":
      "<rootDir>/force-app/test/jest-mocks/lightning/mobileCapabilities"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};
