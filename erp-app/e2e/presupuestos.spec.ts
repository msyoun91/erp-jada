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

test("admin carga renglones a mano y de Catálogo, los edita, duplica y saca", async ({ browser }) => {
  test.setTimeout(180_000);
  const ctx = await browser.newContext({ storageState: "e2e/.auth/admin.json" });
  const page = await ctx.newPage();

  await page.goto("/presupuestos");
  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  await alta.getByLabel("Obra").selectOption({ index: 1 });
  await alta.getByLabel("Nombre", { exact: true }).fill(`Renglones ${marca}`);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  await page.getByRole("link", { name: /Versión 1/ }).click();
  const general = page.getByRole("region", { name: "General" });

  await general.getByRole("button", { name: "A mano" }).click();
  const mano = panel(page);
  await mano.getByLabel("Descripción").fill("Flete cerrado a Pilar");
  await mano.getByLabel(/Precio por unidad/).fill("150.000");
  await mano.getByLabel("Cantidad").fill("2");
  await mano.getByRole("button", { name: "Agregar" }).click();
  await expect(mano.getByText("Va sin puntos")).toBeVisible();
  await mano.getByLabel(/Precio por unidad/).fill("150000");
  await page.screenshot({ path: "e2e/.out/pres-renglon-mano.png", fullPage: true });
  await mano.getByRole("button", { name: "Agregar" }).click();
  await expect(mano).toBeHidden();
  const flete = general.getByRole("listitem").filter({ hasText: "Flete cerrado a Pilar" });
  await expect(flete.getByText("$300.000")).toBeVisible();
  await expect(flete.getByText("A mano")).toBeVisible();

  await flete.getByRole("button", { name: "Más acciones" }).click();
  await flete.getByRole("button", { name: "Editar" }).click();
  const editarMano = panel(page);
  await editarMano.getByLabel("Cantidad").fill("1");
  await editarMano.getByRole("button", { name: "Guardar" }).click();
  await expect(flete.getByText("$150.000")).toBeVisible();

  await general.getByRole("button", { name: "De Catálogo" }).click();
  const cat = panel(page);
  await cat.getByLabel("Designación").fill("V1");
  await cat.getByLabel("Ubicación").fill("Lavadero");
  await cat.getByLabel("Paquete").selectOption({ index: 1 });
  const ancho = cat.getByLabel(/^Ancho/);
  await expect(ancho).toBeVisible();
  await ancho.fill("1.200");
  await expect(cat.getByText("Va sin puntos y con coma")).toBeVisible();
  await expect(cat.getByRole("button", { name: "Agregar" })).toBeDisabled();
  await ancho.fill("1200");
  await cat.getByLabel(/^Alto/).fill("1000");
  await page.screenshot({ path: "e2e/.out/pres-renglon-catalogo.png", fullPage: true });
  await cat.getByRole("button", { name: "Agregar" }).click();
  await expect(cat).toBeHidden();
  const v1 = general.getByRole("listitem").filter({ hasText: "V1" });
  await expect(v1.getByText(/Lavadero/)).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-renglones.png", fullPage: true });

  await v1.getByRole("button", { name: "Más acciones" }).click();
  await v1.getByRole("button", { name: "Duplicar" }).click();
  const dup = panel(page);
  await expect(dup.getByLabel(/^Ancho/)).toHaveValue("1200");
  await dup.getByLabel("Designación").fill("V2");
  await dup.getByRole("button", { name: "Agregar" }).click();
  await expect(dup).toBeHidden();
  const v2 = general.getByRole("listitem").filter({ hasText: "V2" });
  await expect(v2).toBeVisible();

  await v2.getByRole("button", { name: "Más acciones" }).click();
  await v2.getByRole("button", { name: "Editar" }).click();
  const ed = panel(page);
  await expect(ed.getByLabel(/^Alto/)).toHaveValue("1000");
  await ed.getByLabel("Ubicación").fill("Cocina");
  await ed.getByRole("button", { name: "Guardar" }).click();
  await expect(v2.getByText(/Cocina/)).toBeVisible();

  await v2.getByRole("button", { name: "Más acciones" }).click();
  await v2.getByRole("button", { name: "Sacar" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Sacar" }).click();
  await expect(v2).toHaveCount(0);
  await page.screenshot({ path: "e2e/.out/pres-renglones-final.png", fullPage: true });
  await ctx.close();
});
