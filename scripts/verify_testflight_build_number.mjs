import assert from "node:assert/strict";
import crypto from "node:crypto";
import { pathToFileURL } from "node:url";

const APP_STORE_CONNECT_ORIGIN = "https://api.appstoreconnect.apple.com";
const BUILDS_PATH = "/v1/builds";
const MAX_BUILD_PAGES = 100;

function parsePositiveInteger(value, label) {
  const normalized = String(value ?? "").trim();
  if (!/^[1-9][0-9]*$/.test(normalized)) {
    throw new Error(`${label} must be a positive integer.`);
  }
  return Number(normalized);
}

function usageError() {
  return new Error(
    "Usage: verify_testflight_build_number.mjs <candidate-build-number> | --auth-only | --self-test",
  );
}

export function parseInvocation(arguments_) {
  if (arguments_.length !== 1) {
    throw usageError();
  }

  const [argument] = arguments_;
  if (argument === "--self-test") {
    return { mode: "self-test" };
  }
  if (argument === "--auth-only") {
    return { mode: "auth-only" };
  }
  if (argument.startsWith("--")) {
    throw usageError();
  }
  return { mode: "candidate", candidate: argument };
}

function normalizedBuildNumbers(existingValues) {
  return existingValues
    .map((value) => String(value ?? "").trim())
    .filter((value) => /^[1-9][0-9]*$/.test(value))
    .map(Number);
}

function latestBuildNumber(existingValues) {
  const existing = normalizedBuildNumbers(existingValues);
  return existing.length === 0 ? null : Math.max(...existing);
}

export function evaluateBuildNumber(candidateValue, existingValues) {
  const candidate = parsePositiveInteger(candidateValue, "Candidate build number");
  const existing = normalizedBuildNumbers(existingValues);

  if (existing.includes(candidate)) {
    throw new Error(`Build ${candidate} already exists in App Store Connect.`);
  }

  const latest = existing.length === 0 ? null : Math.max(...existing);
  if (latest !== null && candidate <= latest) {
    throw new Error(
      `Build ${candidate} is not newer than App Store Connect build ${latest}.`,
    );
  }

  return { candidate, latest };
}

export function selectLookupResult(invocation, existingValues) {
  if (invocation.mode === "auth-only") {
    return { mode: "auth-only", latest: latestBuildNumber(existingValues) };
  }
  if (invocation.mode === "candidate") {
    return {
      mode: "candidate",
      ...evaluateBuildNumber(invocation.candidate, existingValues),
    };
  }
  throw new Error(`Unsupported lookup mode ${invocation.mode}.`);
}

function base64URL(value) {
  return Buffer.from(value).toString("base64url");
}

function createAppStoreConnectToken({ keyID, issuerID, privateKey }) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64URL(JSON.stringify({ alg: "ES256", kid: keyID, typ: "JWT" }));
  const payload = base64URL(
    JSON.stringify({
      iss: issuerID,
      iat: now - 30,
      exp: now + 10 * 60,
      aud: "appstoreconnect-v1",
    }),
  );
  const signingInput = `${header}.${payload}`;
  const signature = crypto.sign("sha256", Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  });
  return `${signingInput}.${base64URL(signature)}`;
}

export function validateBuildLookupURL(value, appID) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error("App Store Connect returned an invalid build-pagination URL.");
  }

  const appFilters = url.searchParams.getAll("filter[app]");
  if (
    url.origin !== APP_STORE_CONNECT_ORIGIN ||
    url.pathname !== BUILDS_PATH ||
    url.username !== "" ||
    url.password !== "" ||
    url.hash !== "" ||
    appFilters.length !== 1 ||
    appFilters[0] !== appID
  ) {
    throw new Error(
      "App Store Connect returned an unsafe build-pagination URL.",
    );
  }
  return url.toString();
}

async function fetchExistingBuildNumbers({ appID, token }) {
  const initialURL = new URL(BUILDS_PATH, APP_STORE_CONNECT_ORIGIN);
  initialURL.searchParams.set("filter[app]", appID);
  initialURL.searchParams.set("sort", "-uploadedDate");
  initialURL.searchParams.set("limit", "200");

  const versions = [];
  const visitedURLs = new Set();
  let nextURL = validateBuildLookupURL(initialURL.toString(), appID);
  while (nextURL) {
    if (visitedURLs.has(nextURL) || visitedURLs.size >= MAX_BUILD_PAGES) {
      throw new Error("App Store Connect build pagination did not terminate safely.");
    }
    visitedURLs.add(nextURL);

    const response = await fetch(nextURL, {
      redirect: "error",
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!response.ok) {
      throw new Error(
        `App Store Connect build lookup failed with HTTP ${response.status}.`,
      );
    }

    const payload = await response.json();
    for (const build of payload.data ?? []) {
      versions.push(build.attributes?.version);
    }
    const candidateNextURL = payload.links?.next ?? null;
    nextURL =
      candidateNextURL === null
        ? null
        : validateBuildLookupURL(candidateNextURL, appID);
  }
  return versions;
}

function requiredEnvironment(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable ${name}.`);
  }
  return value;
}

export function validateCredentialIdentifiers({ keyID, issuerID, appID }) {
  if (!/^[A-Z0-9]{10}$/.test(keyID)) {
    throw new Error("App Store Connect API key ID is not canonical.");
  }
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      issuerID,
    )
  ) {
    throw new Error("App Store Connect API issuer ID is not canonical.");
  }
  if (!/^[1-9][0-9]*$/.test(appID)) {
    throw new Error("App Store Connect app ID is not canonical.");
  }
}

function runSelfTest() {
  assert.deepEqual(parseInvocation(["--self-test"]), { mode: "self-test" });
  assert.deepEqual(parseInvocation(["--auth-only"]), { mode: "auth-only" });
  assert.deepEqual(parseInvocation(["14"]), {
    mode: "candidate",
    candidate: "14",
  });
  assert.throws(() => parseInvocation([]), /Usage:/);
  assert.throws(() => parseInvocation(["--unknown"]), /Usage:/);
  assert.throws(() => parseInvocation(["--auth-only", "14"]), /Usage:/);

  assert.doesNotThrow(() =>
    validateCredentialIdentifiers({
      keyID: "W3UF745JN4",
      issuerID: "ba45844d-8147-4d78-932b-bfdbbbc55dc0",
      appID: "6807022780",
    }),
  );
  assert.throws(
    () =>
      validateCredentialIdentifiers({
        keyID: "unsafe/path",
        issuerID: "ba45844d-8147-4d78-932b-bfdbbbc55dc0",
        appID: "6807022780",
      }),
    /key ID/,
  );
  assert.throws(
    () =>
      validateCredentialIdentifiers({
        keyID: "W3UF745JN4",
        issuerID: "not-a-uuid",
        appID: "6807022780",
      }),
    /issuer ID/,
  );
  assert.throws(
    () =>
      validateCredentialIdentifiers({
        keyID: "W3UF745JN4",
        issuerID: "ba45844d-8147-4d78-932b-bfdbbbc55dc0",
        appID: "../../other",
      }),
    /app ID/,
  );

  const validLookupURL =
    "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=6807022780&limit=200";
  assert.equal(
    validateBuildLookupURL(validLookupURL, "6807022780"),
    validLookupURL,
  );
  assert.throws(
    () =>
      validateBuildLookupURL(
        "https://example.com/v1/builds?filter%5Bapp%5D=6807022780",
        "6807022780",
      ),
    /unsafe/,
  );
  assert.throws(
    () =>
      validateBuildLookupURL(
        "https://api.appstoreconnect.apple.com/v1/apps?filter%5Bapp%5D=6807022780",
        "6807022780",
      ),
    /unsafe/,
  );
  assert.throws(
    () =>
      validateBuildLookupURL(
        "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=1",
        "6807022780",
      ),
    /unsafe/,
  );

  assert.deepEqual(
    selectLookupResult({ mode: "auth-only" }, ["13", "12", null, "invalid"]),
    { mode: "auth-only", latest: 13 },
  );
  assert.deepEqual(selectLookupResult({ mode: "auth-only" }, []), {
    mode: "auth-only",
    latest: null,
  });
  assert.deepEqual(
    selectLookupResult({ mode: "candidate", candidate: "14" }, ["13", "12"]),
    { mode: "candidate", candidate: 14, latest: 13 },
  );
  assert.throws(
    () =>
      selectLookupResult(
        { mode: "candidate", candidate: "13" },
        ["13", "12"],
      ),
    /already exists/,
  );

  assert.deepEqual(evaluateBuildNumber("14", ["13", "12"]), {
    candidate: 14,
    latest: 13,
  });
  assert.throws(
    () => evaluateBuildNumber("13", ["13", "12"]),
    /already exists/,
  );
  assert.throws(
    () => evaluateBuildNumber("12", ["13", "12"]),
    /already exists/,
  );
  assert.throws(
    () => evaluateBuildNumber("11", ["13", "12"]),
    /not newer/,
  );
  assert.throws(() => evaluateBuildNumber("1.4", ["13"]), /positive integer/);
  console.log("TestFlight build-number guard self-test passed.");
}

async function main() {
  const invocation = parseInvocation(process.argv.slice(2));
  if (invocation.mode === "self-test") {
    runSelfTest();
    return;
  }

  const keyID = requiredEnvironment("APP_STORE_CONNECT_API_KEY_ID");
  const issuerID = requiredEnvironment("APP_STORE_CONNECT_API_ISSUER_ID");
  const appID = requiredEnvironment("APP_STORE_CONNECT_APP_ID");
  validateCredentialIdentifiers({ keyID, issuerID, appID });
  const privateKey = Buffer.from(
    requiredEnvironment("APP_STORE_CONNECT_API_KEY_BASE64"),
    "base64",
  ).toString("utf8");

  const signingKey = crypto.createPrivateKey(privateKey);
  if (signingKey.asymmetricKeyType !== "ec") {
    throw new Error("App Store Connect API key must be an EC private key.");
  }
  const token = createAppStoreConnectToken({
    keyID,
    issuerID,
    privateKey: signingKey,
  });
  const existing = await fetchExistingBuildNumbers({ appID, token });
  const result = selectLookupResult(invocation, existing);
  const prior = result.latest === null ? "none" : String(result.latest);
  if (result.mode === "auth-only") {
    console.log(
      `Authenticated App Store Connect build lookup succeeded; latest build is ${prior}.`,
    );
    return;
  }
  console.log(
    `Verified candidate Build ${result.candidate}; latest App Store Connect build is ${prior}.`,
  );
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
