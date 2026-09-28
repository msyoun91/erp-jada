import { test, expect, type Page } from "@playwright/test";
import { asegurarAprobador, como, crearIgual, panel, tarjeta } from "./comun";

// Tramo 3 de Obras y Contactos: el admin aprueba altas. Tiene Edificio Norte y
// a Lucía Pérez; Juan (tester) carga tres obras en la misma dirección y a Lucía
// otra vez, le avisa a ciegas, entran congeladas, y el admin aprueba una,
// rechaza otra y marca la tercera como "es la misma".
const marca = `Zqx${Date.now() % 100000}`;
const direccion = `Av. Rivadavia ${5000 + (Date.now() % 1000)}`;
const base = `Edificio Norte ${marca}`;
const aprobar = `Edificio Norte ${marca} A`;
const rechazar = `Edificio Norte ${marca} R`;
const misma = `Edificio Norte ${marca} M`;
const lucia = `Lucía Pérez ${marca}`;
const luciaDeJuan = `Lucia Perez ${marca}`;

test.describe.configure({ mode: "serial" });

const urls: Record<string, string> = {};

async function nuevaObra(page: Page, nombre: string, origen = "Llamado") {
  await page.goto("/obras");
  await page.getByRole("button", { name: "Nueva obra" }).click();
  const alta = panel(page);
  await alta.getByLabel("Nombre", { exact: true }).fill(nombre);
  await alta.getByLabel("Dirección").fill(direccion);
  await alta.getByLabel("Tipo de obra").selectOption({ label: "Edificio residencial" });
  await alta.getByLabel("Origen").selectOption({ label: origen });
  return alta;
}

test("el admin recibe Aprobar altas y carga lo existente", async ({ browser }) => {
  const { ctx, page } = await como(browser, "admin");

  await asegurarAprobador(page);

  // Con la función, lo suyo no se congela.
  const alta = await nuevaObra(page, base);
  urls.base = await crearIgual(page, alta, "Crear obra", /\/obras\/[0-9a-f-]{36}$/);
  await expect(page.getByText("espera aprobación")).toHaveCount(0);

  await page.goto("/contactos");
  await page.getByRole("button", { name: "Nueva persona" }).click();
  const persona = panel(page);
  await persona.getByLabel("Nombre").fill(lucia);
  await persona.getByLabel("Teléfono").fill(`11 4${marca.slice(3).padStart(5, "0")}`);
  await crearIgual(page, persona, "Crear persona", /\/contactos\/personas\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("heading", { name: lucia })).toBeVisible();

  await ctx.close();
});

test("Juan recibe el aviso a ciegas y sus altas quedan por aprobar", async ({ browser }) => {
  test.setTimeout(120_000);
  const { ctx, page } = await como(browser, "tester");

  // Primera: el aviso frena y el botón pasa a "Crear igual".
  let alta = await nuevaObra(page, aprobar);
  await alta.getByRole("button", { name: "Crear obra" }).click();
  await expect(alta.getByText(/^Se parece a otras? obras?$/)).toBeVisible();
  await expect(alta.getByRole("listitem").filter({ hasText: base }).filter({ hasText: "· Admin" })).toBeVisible();
  await alta.getByRole("button", { name: "Crear igual" }).click();
  await expect(page).toHaveURL(/\/obras\/[0-9a-f-]{36}$/);
  urls.aprobar = new URL(page.url()).pathname;
  await expect(page.getByText("Se parece a otra obra y espera aprobación")).toBeVisible();
  await expect(page.getByRole("button", { name: "Sumar participante" })).toHaveCount(0);

  alta = await nuevaObra(page, rechazar);
  await alta.getByRole("button", { name: "Crear obra" }).click();
  await expect(alta.getByText(/^Se parece a otras? obras?$/)).toBeVisible();
  // La suya congelada también cuenta, con link.
  await expect(alta.getByRole("link", { name: aprobar })).toBeVisible();
  await alta.getByRole("button", { name: "Crear igual" }).click();
  await expect(page).toHaveURL(/\/obras\/[0-9a-f-]{36}$/);
  urls.rechazar = new URL(page.url()).pathname;

  // La tercera trae a Lucía como referente: el "¿Quién?" avisa en vivo.
  alta = await nuevaObra(page, misma, "Referente");
  await alta.getByLabel("Buscar persona o empresa").fill(luciaDeJuan);
  await alta.getByRole("button", { name: `Crear «${luciaDeJuan}» como persona` }).click();
  await expect(alta.getByText(/^Se parece a otras? personas?$/)).toBeVisible();
  await expect(alta.getByText(`${lucia}, de Admin`, { exact: true })).toBeVisible();
  await alta.getByRole("button", { name: "Crear obra" }).click();
  await expect(alta.getByText(/^Se parece a otras? obras?$/)).toBeVisible();
  await alta.getByRole("button", { name: "Crear igual" }).click();
  await expect(page).toHaveURL(/\/obras\/[0-9a-f-]{36}$/);
  urls.misma = new URL(page.url()).pathname;

  // La marca en la lista.
  await page.goto("/obras");
  for (const nombre of [aprobar, rechazar, misma]) {
    await expect(page.getByRole("link", { name: new RegExp(nombre) })).toContainText("Por aprobar");
  }

  await ctx.close();
});

test("el admin aprueba, rechaza y resuelve como la misma", async ({ browser }) => {
  test.setTimeout(120_000);
  const { ctx, page } = await como(browser, "admin");

  await page.goto("/obras");
  await page.getByRole("link", { name: /^Por aprobar/ }).click();
  await expect(page).toHaveURL(/\/obras\/por-aprobar$/);

  const a = tarjeta(page, aprobar);
  await expect(a).toContainText("Alta");
  await expect(a.getByText(base, { exact: true })).toBeVisible();
  await a.getByRole("button", { name: "Aprobar" }).click();
  await expect(page.getByText("Obra aprobada")).toBeVisible();
  await expect(a).toHaveCount(0);

  const r = tarjeta(page, rechazar);
  await r.getByRole("button", { name: "Rechazar" }).click();
  const modal = panel(page);
  await modal.getByLabel("Motivo").fill(`Es la de Admin ${marca}`);
  await modal.getByRole("button", { name: "Rechazar" }).click();
  await expect(page.getByText("Obra rechazada")).toBeVisible();
  await expect(r).toHaveCount(0);

  const m = tarjeta(page, misma);
  await expect(m).toContainText(`Al aprobarla se vincula ${luciaDeJuan}`);
  await m.getByRole("listitem").filter({ has: page.getByText(base, { exact: true }) }).getByRole("button", { name: "Es la misma" }).click();
  const confirmar = panel(page);
  await expect(confirmar).toContainText(`se suma a "${base}"`);
  await confirmar.getByRole("button", { name: "Es la misma" }).click();
  await expect(page.getByText("Resuelta como la misma")).toBeVisible();
  await expect(m).toHaveCount(0);

  // Lucía de Juan sigue por aprobar en Contactos: tiene otro teléfono, se aprueba.
  await page.goto("/contactos");
  await page.getByRole("link", { name: /^Por aprobar/ }).click();
  await expect(page).toHaveURL(/\/contactos\/por-aprobar$/);
  const l = tarjeta(page, luciaDeJuan);
  await expect(l.getByText(lucia, { exact: true })).toBeVisible();
  await l.getByRole("button", { name: "Aprobar" }).click();
  await expect(page.getByText("Aprobada", { exact: true })).toBeVisible();
  await expect(l).toHaveCount(0);

  await ctx.close();
});

test("Juan ve cómo quedó cada una", async ({ browser }) => {
  const { ctx, page } = await como(browser, "tester");

  await page.goto(urls.aprobar);
  await expect(page.getByRole("heading", { name: aprobar })).toBeVisible();
  await expect(page.getByText("espera aprobación")).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Sumar participante" })).toBeVisible();

  // Es participante de la de Admin, con Lucía de referente.
  await page.goto(urls.base);
  await expect(page.getByRole("heading", { name: base })).toBeVisible();
  await expect(page.getByRole("listitem").filter({ hasText: luciaDeJuan })).toContainText("Referente");

  await page.goto("/obras");
  await expect(page.getByRole("link", { name: new RegExp(rechazar) })).toHaveCount(0);
  await expect(page.getByRole("link", { name: new RegExp(misma) })).toHaveCount(0);

  await ctx.close();
});
