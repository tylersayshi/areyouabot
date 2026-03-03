const AREYOUABOT_REPO = "tylersayshi/areyouabot";
const GITHUB_OIDC_ISSUER = "https://token.actions.githubusercontent.com";

interface Env {
  GITHUB_TOKEN: string;
}

interface ReportBody {
  username: string;
  reason: string;
  evidence_url: string;
  repository: string;
}

interface JWK {
  kty: string;
  n: string;
  e: string;
  kid: string;
  alg: string;
}

interface JWKS {
  keys: JWK[];
}

interface JWTHeader {
  alg: string;
  kid: string;
}

interface JWTPayload {
  iss: string;
  aud: string;
  exp: number;
  repository: string;
  [key: string]: unknown;
}

function base64UrlDecode(str: string): Uint8Array {
  const padded = str.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function decodeJWTPart<T>(part: string): T {
  const decoded = new TextDecoder().decode(base64UrlDecode(part));
  return JSON.parse(decoded) as T;
}

async function importJWK(jwk: JWK): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );
}

async function fetchJWKS(issuer: string): Promise<JWKS> {
  const url = `${issuer}/.well-known/jwks`;
  const resp = await fetch(url, {
    cf: { cacheTtlByStatus: { "200-299": 600 } },
  } as RequestInit);
  if (!resp.ok) {
    throw new Error(`Failed to fetch JWKS: ${resp.status}`);
  }
  return resp.json();
}

async function verifyJWT(
  token: string,
  issuer: string,
  audience: string
): Promise<JWTPayload> {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new Error("Invalid JWT format");
  }

  const header = decodeJWTPart<JWTHeader>(parts[0]);
  const payload = decodeJWTPart<JWTPayload>(parts[1]);

  // Validate claims
  if (payload.iss !== issuer) {
    throw new Error(`Invalid issuer: ${payload.iss}`);
  }
  if (payload.aud !== audience) {
    throw new Error(`Invalid audience: ${payload.aud}`);
  }
  if (payload.exp < Math.floor(Date.now() / 1000)) {
    throw new Error("Token expired");
  }

  // Verify signature
  const jwks = await fetchJWKS(issuer);
  const jwk = jwks.keys.find((k) => k.kid === header.kid);
  if (!jwk) {
    throw new Error(`No matching key found for kid: ${header.kid}`);
  }

  const key = await importJWK(jwk);
  const signatureBytes = base64UrlDecode(parts[2]);
  const dataBytes = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);

  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    signatureBytes,
    dataBytes
  );

  if (!valid) {
    throw new Error("Invalid JWT signature");
  }

  return payload;
}

async function fetchTrustedRepos(areyouabotRepo: string): Promise<string[]> {
  const url = `https://raw.githubusercontent.com/${areyouabotRepo}/main/data/trusted-repos.json`;
  const resp = await fetch(url, {
    cf: { cacheTtlByStatus: { "200-299": 60 } },
  } as RequestInit);
  if (!resp.ok) {
    throw new Error(`Failed to fetch trusted repos: ${resp.status}`);
  }
  return resp.json();
}

async function createIssue(
  repo: string,
  token: string,
  report: ReportBody
): Promise<void> {
  const body = `### Username

${report.username}

### Reporting Repository

${report.repository}

### Reason

${report.reason}

### Evidence URL

${report.evidence_url}`;

  const resp = await fetch(
    `https://api.github.com/repos/${repo}/issues`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github+json",
        "User-Agent": "areyouabot-worker",
        "X-GitHub-Api-Version": "2022-11-28",
      },
      body: JSON.stringify({
        title: `[REPORT] ${report.username}`,
        body,
        labels: ["report"],
      }),
    }
  );

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Failed to create issue: ${resp.status} ${text}`);
  }
}

function jsonResponse(
  data: { success: boolean; message: string },
  status = 200
): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") {
      return jsonResponse(
        { success: false, message: "Method not allowed" },
        405
      );
    }

    // Extract OIDC token
    const authHeader = request.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse(
        { success: false, message: "Missing Authorization header" },
        401
      );
    }
    const token = authHeader.slice(7);

    // Parse request body
    let report: ReportBody;
    try {
      report = await request.json();
    } catch {
      return jsonResponse(
        { success: false, message: "Invalid JSON body" },
        400
      );
    }

    if (!report.username || !report.reason) {
      return jsonResponse(
        { success: false, message: "username and reason are required" },
        400
      );
    }

    // Verify JWT
    const audience = new URL(request.url).origin;
    let payload: JWTPayload;
    try {
      payload = await verifyJWT(token, GITHUB_OIDC_ISSUER, audience);
    } catch (err) {
      return jsonResponse(
        {
          success: false,
          message: `JWT verification failed: ${(err as Error).message}`,
        },
        403
      );
    }

    // Check trusted repos
    const callerRepo = payload.repository;
    if (!callerRepo) {
      return jsonResponse(
        { success: false, message: "JWT missing repository claim" },
        403
      );
    }

    let trustedRepos: string[];
    try {
      trustedRepos = await fetchTrustedRepos(AREYOUABOT_REPO);
    } catch (err) {
      return jsonResponse(
        {
          success: false,
          message: `Failed to fetch trusted repos: ${(err as Error).message}`,
        },
        500
      );
    }

    if (!trustedRepos.includes(callerRepo)) {
      return jsonResponse(
        {
          success: false,
          message: `Repository ${callerRepo} is not in the trusted reporter network`,
        },
        403
      );
    }

    // Create issue
    try {
      await createIssue(AREYOUABOT_REPO, env.GITHUB_TOKEN, {
        ...report,
        repository: callerRepo,
      });
    } catch (err) {
      return jsonResponse(
        {
          success: false,
          message: `Failed to create issue: ${(err as Error).message}`,
        },
        500
      );
    }

    return jsonResponse({
      success: true,
      message: `Report submitted for ${report.username}`,
    });
  },
} satisfies ExportedHandler<Env>;
