import { test, expect } from "@playwright/test";

test("admin ve el listado de usuarios", async ({ page }) => {
  await page.goto("/usuarios");
  await expect(page.getByRole("heading", { name: "Usuarios", level: 1 })).toBeVisible();
});

test("con sesión, /login vuelve al inicio", async ({ page }) => {
  await page.goto("/login");
  await expect(page).toHaveURL(/\/$/);
});
