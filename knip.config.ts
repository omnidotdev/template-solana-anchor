import type { KnipConfig } from "knip";

/**
 * Knip configuration.
 * @see https://knip.dev/reference/configuration
 */
const knipConfig: KnipConfig = {
  entry: ["scripts/**/*.ts", "tests/**/*.ts"],
  project: ["scripts/**/*.ts", "tests/**/*.ts"],
  ignore: ["target/**", "node_modules/**"],
  ignoreExportsUsedInFile: {
    interface: true,
    type: true,
  },
};

export default knipConfig;
