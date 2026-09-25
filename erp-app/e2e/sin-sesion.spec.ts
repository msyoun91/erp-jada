import { test, expect } from "@playwright/test";

test("sin sesión, un deep link manda a login y conserva el destino", async ({ page }) => {
  await page.goto("/tareas");
  await expect(page).toHaveURL(/\/login\?next=%2Ftareas$/);
  await expect(page.getByRole("heading", { name: "Ingresar a ERP JADA" })).toBeAttached();
});
