import { test, expect } from "@playwright/test";

test("tester entra al ERP", async ({ page }) => {
  await page.goto("/");
  await expect(page).not.toHaveURL(/\/login/);
});
