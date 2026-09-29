import { expect, type Browser, type Locator, type Page } from "@playwright/test";

export function panel(page: Page) {
  return page.getByRole("dialog").last();
}

export async function como(browser: Browser, quien: "admin" | "tester" | "tester2") {
  const ctx = await browser.newContext({ storageState: `e2e/.auth/${quien}.json` });
  return { ctx, page: await ctx.newPage() };
}

// Las corridas anteriores dejan altas con el mismo nombre base: el aviso a
// ciegas frena el primer intento y el segundo pasa (congelada, si no tiene
// "Aprobar altas").
export async function crearIgual(page: Page, alta: Locator, boton: string, ruta: RegExp) {
  await alta.getByRole("button", { name: boton }).click();
  const igual = alta.getByRole("button", { name: /igual$/ });
  await expect.poll(async () => (await igual.isVisible()) || ruta.test(page.url())).toBe(true);
  if (await igual.isVisible()) await igual.click();
  await expect(page).toHaveURL(ruta);
  return new URL(page.url()).pathname;
}

// Mismo caso en un panel que no cambia de página (vincular): el aviso se ve
// y el mismo botón pasa la segunda vez.
export async function confirmarConAviso(alta: Locator, boton: string) {
  await alta.getByRole("button", { name: boton }).click();
  const aviso = alta.getByText(/^Se parece a/);
  await expect.poll(async () => (await aviso.isVisible()) || !(await alta.isVisible())).toBe(true);
  if (await aviso.isVisible()) await alta.getByRole("button", { name: boton }).click();
  await expect(alta).toBeHidden();
}

export async function asegurarAprobador(page: Page) {
  await page.goto("/usuarios");
  const fila = page.locator("div.row").filter({ has: page.getByText("Admin", { exact: true }) });
  await fila.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Permisos" }).click();
  const permisos = panel(page);
  let cambio = false;
  for (const modulo of ["Obras", "Contactos"]) {
    const bloque = permisos.locator("div.border-b").filter({ has: page.getByText(modulo, { exact: true }) });
    const casilla = bloque.getByRole("checkbox", { name: /^Aprobar altas/ });
    if (!(await casilla.isChecked())) {
      await casilla.check();
      cambio = true;
    }
  }
  await permisos.getByRole("button", { name: cambio ? "Guardar" : "Cancelar" }).click();
  await expect(permisos).toBeHidden();
}

export function tarjeta(page: Page, nombre: string | RegExp) {
  return page.locator("div.card").filter({ has: page.getByRole("heading", { name: nombre, exact: true }) });
}

// El admin aprueba lo de esta corrida que quedó por aprobar en Obras y en Contactos.
export async function aprobarPendientes(browser: Browser, marca: string) {
  const { ctx, page } = await como(browser, "admin");
  await asegurarAprobador(page);
  for (const ruta of ["/obras/por-aprobar", "/contactos/por-aprobar"]) {
    await page.goto(ruta);
    // `count()` no espera: primero, que termine de cargar.
    await expect(page.locator("div.card").or(page.getByText("Nada por aprobar")).first()).toBeVisible();
    const pendientes = tarjeta(page, new RegExp(marca));
    while ((await pendientes.count()) > 0) {
      const antes = await pendientes.count();
      await pendientes.first().getByRole("button", { name: "Aprobar" }).click();
      await expect(pendientes).toHaveCount(antes - 1);
    }
  }
  await ctx.close();
}
