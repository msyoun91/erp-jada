import { defineConfig } from "@playwright/test";

// Credenciales de los usuarios de prueba: fuera del repo (.env* está ignorado).
process.loadEnvFile(".env.test");

const baseURL = "http://localhost:3000";

// La base no es de producción pero tiene datos: lo que crea un test lleva marcador Zqx<nro> (ver decisiones/global/infra.md).
export default defineConfig({
  testDir: "e2e",
  fullyParallel: true,
  reporter: "list",
  // `npm run dev` compila cada ruta la primera vez que se abre.
  expect: { timeout: 15_000 },
  use: { baseURL, trace: "retain-on-failure" },
  projects: [
    { name: "setup", testMatch: /auth\.setup\.ts/ },
    { name: "sin-sesion", testMatch: /sin-sesion\.spec\.ts/ },
    {
      name: "admin",
      testMatch: /admin\.spec\.ts/,
      dependencies: ["setup"],
      use: { storageState: "e2e/.auth/admin.json" },
    },
    {
      name: "tester",
      testMatch: /tester\.spec\.ts/,
      dependencies: ["setup"],
      use: { storageState: "e2e/.auth/tester.json" },
    },
    // Flujos entre usuarios: cada test abre los contextos que necesita.
    { name: "obras", testMatch: /obras\.spec\.ts/, dependencies: ["setup"] },
  ],
  webServer: { command: "npm run dev", url: baseURL, reuseExistingServer: true },
});
