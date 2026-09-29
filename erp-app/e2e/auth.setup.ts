import { test as setup, expect } from "@playwright/test";

const usuarios = [
  { nombre: "admin", email: process.env.E2E_ADMIN_EMAIL, password: process.env.E2E_ADMIN_PASSWORD },
  { nombre: "tester", email: process.env.E2E_TESTER_EMAIL, password: process.env.E2E_TESTER_PASSWORD },
  { nombre: "tester2", email: process.env.E2E_TESTER2_EMAIL, password: process.env.E2E_TESTER2_PASSWORD },
];

for (const usuario of usuarios) {
  setup(`login ${usuario.nombre}`, async ({ page }) => {
    if (!usuario.email || !usuario.password) {
      throw new Error(`Faltan las credenciales de ${usuario.nombre} en .env.test`);
    }
    await page.goto("/login");
    await page.getByLabel("Email").fill(usuario.email);
    await page.getByLabel("Contraseña", { exact: true }).fill(usuario.password);
    await page.getByRole("button", { name: "Ingresar" }).click();
    // En dev, el primer ingreso compila la página de inicio: tarda más que el default.
    await expect(page).not.toHaveURL(/\/login/, { timeout: 30_000 });
    await page.context().storageState({ path: `e2e/.auth/${usuario.nombre}.json` });
  });
}
