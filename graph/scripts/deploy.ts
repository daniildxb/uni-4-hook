import dotenv from "dotenv";
import path from "path";
dotenv.config({ path: path.resolve(__dirname, "../../.env") });
import { execAsync, getNetwork } from "./utils";
import { version } from "../package.json";
import { networks as ALLOWED_NETWORKS } from "../src/config";


interface EnvVariables {
  GOLDSKY_API_KEY?: string;
  SUBGRAPH_SLUG?: string;
}

const { GOLDSKY_API_KEY, SUBGRAPH_SLUG } = process.env as EnvVariables;

type Network = (typeof ALLOWED_NETWORKS)[number];


const validateEnv = (): void => {
  if (!GOLDSKY_API_KEY) {
    throw new Error("GOLDSKY_API_KEY is not set in the environment variables.");
  }
  if (!SUBGRAPH_SLUG) {
    throw new Error("SUBGRAPH_SLUG is not set in the environment variables.");
  }
};

const validateArgs = (): void => {
  const network = getNetwork();

  if (!network) {
    throw new Error(
      "Network not specified. Please set NETWORK environment variable or pass it as an argument."
    );
  }
  if (!ALLOWED_NETWORKS.includes(network as Network)) {
    throw new Error(
      `Invalid network specified. Available networks: ${ALLOWED_NETWORKS.join(", ")}`
    );
  }
};

const getDeployCommands = (
  buildDirectory: string,
  subgraphSlug: string
): { authCommand: string; deployCommand: string } => {
    return {
        authCommand: `goldsky login --token ${GOLDSKY_API_KEY}`,
        deployCommand: `goldsky subgraph deploy ${subgraphSlug}-${version} --path ${buildDirectory}`,
    }
};

const deploy = async (): Promise<void> => {
    const network = getNetwork();
    if (!network || !SUBGRAPH_SLUG) return;

    const srcDirectory = path.resolve(__dirname, `../src`);
    const buildDirectory = path.resolve(__dirname, `../build/${network}`);

    const { authCommand, deployCommand } = getDeployCommands(buildDirectory, `${network}/${SUBGRAPH_SLUG}`);
    const command = [
        authCommand, 
        `cd ${srcDirectory}`,
        deployCommand
    ].join(" && ");

    await execAsync(command)
}


const run = async (): Promise<void> => {
  try {
    validateArgs();
    validateEnv();
    await deploy();
  } catch (error) {
    console.error("Error during deployment:", error);
    process.exit(1);
  }
}

if (require.main === module) {
  run();
}