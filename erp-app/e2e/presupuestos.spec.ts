import { test, expect } from "@playwright/test";
import { panel } from "./comun";

const marca = `Zqx${Date.now() % 100000}`;
const nombre = `Aberturas ${marca}`;

test("admin da de alta un presupuesto y ve la lista, la ficha y la versión", async ({ browser }) => {
  test.setTimeout(120_000);
  const ctx = await browser.newContext({ storageState: "e2e/.auth/admin.json" });
  const page = await ctx.newPage();

  await page.goto("/presupuestos");
  await expect(page.getByRole("button", { name: "Nuevo presupuesto" })).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-lista-vacia.png", fullPage: true });

  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  const obra = alta.getByLabel("Obra");
  await obra.selectOption({ index: 1 });
  await alta.getByLabel("Nombre", { exact: true }).fill(nombre);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("heading", { name: new RegExp(nombre) })).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-ficha.png", fullPage: true });

  await page.getByRole("link", { name: /Versión 1/ }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("heading", { name: "Versión 1" })).toBeVisible();
  await expect(page.getByRole("region", { name: "General" }).getByText("Sin renglones.")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-version.png", fullPage: true });

  await page.getByRole("button", { name: "Editar" }).click();
  const datos = panel(page);
  await datos.getByLabel("Nombre de la variante").fill("Aluminio");
  await datos.getByLabel("IVA").selectOption("false");
  await datos.getByLabel("Descuento").fill("5");
  await page.screenshot({ path: "e2e/.out/pres-version-datos.png", fullPage: true });
  await datos.getByRole("button", { name: "Guardar" }).click();
  await expect(page.getByRole("heading", { name: "Versión 1 · Aluminio" })).toBeVisible();
  await expect(page.getByText("IVA incluido · Descuento 5 %")).toBeVisible();

  await page.getByRole("button", { name: "Nueva sección" }).click();
  const nueva = panel(page);
  await nueva.getByLabel("Nombre").fill("Colocación");
  await nueva.getByLabel("IVA").selectOption("10.5");
  await nueva.getByRole("button", { name: "Crear sección" }).click();
  const colocacion = page.getByRole("region", { name: "Colocación" });
  await expect(colocacion.getByText("ARS · IVA 10,5 %")).toBeVisible();
  await expect(page.locator("section").first()).toHaveAttribute("aria-label", "General");

  await colocacion.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Subir" }).click();
  await expect(page.locator("section").first()).toHaveAttribute("aria-label", "Colocación");

  await page.getByRole("button", { name: "Más acciones" }).first().click();
  await page.getByRole("button", { name: "Todas las secciones…" }).click();
  const todas = panel(page);
  await todas.getByLabel("IVA").selectOption("21");
  await todas.getByRole("button", { name: "Cambiar todas" }).click();
  await expect(colocacion.getByText("ARS · IVA 21 %")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-version-secciones.png", fullPage: true });

  await colocacion.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Sacar" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Sacar" }).click();
  await expect(colocacion).toHaveCount(0);
  await expect(page.getByRole("region", { name: "General" }).getByRole("button", { name: "Más acciones" })).toBeVisible();

  await page.goto("/presupuestos");
  await expect(page.getByText(nombre)).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-lista.png", fullPage: true });
  for (const filtro of ["Esperan mi autorización", "Devueltas"]) {
    await page.getByRole("button", { name: new RegExp(filtro) }).click();
    await page.screenshot({ path: `e2e/.out/pres-${filtro.slice(0, 6)}.png`, fullPage: true });
  }
  await ctx.close();
});
