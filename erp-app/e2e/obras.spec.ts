import { test, expect, type Page } from "@playwright/test";

// Tramo 1 de Obras y Contactos: Juan (tester) carga Torre Belgrano con Marta de
// referente, suma a Pedro (Tester 2), le vincula una constructora y ve el
// contacto de Marta; el admin la ve después. Todo lleva el marcador.
const marca = `Zqx${Date.now() % 100000}`;
const obra = `Torre Belgrano ${marca}`;
const marta = `Marta Gómez ${marca}`;
const constructora = `Constructora Sur ${marca}`;

test.describe.configure({ mode: "serial" });

let urlObra = "";

async function panel(page: Page) {
  return page.getByRole("dialog").last();
}

test("Juan carga la obra con Marta de referente", async ({ browser }) => {
  const ctx = await browser.newContext({ storageState: "e2e/.auth/tester.json" });
  const page = await ctx.newPage();

  await page.goto("/obras");
  await page.getByRole("button", { name: "Nueva obra" }).click();
  const alta = await panel(page);
  await alta.getByLabel("Nombre", { exact: true }).fill(obra);
  await alta.getByLabel("Dirección").fill("Av. Cabildo 1234");
  await alta.getByLabel("Tipo de obra").selectOption({ label: "Edificio residencial" });
  await alta.getByLabel("Origen").selectOption({ label: "Referente" });
  await alta.getByLabel("Buscar persona o empresa").fill(marta);
  await alta.getByRole("button", { name: `Crear «${marta}» como persona` }).click();
  await alta.getByLabel("Teléfono").fill("11 5555 1234");
  await alta.getByRole("button", { name: "Crear obra" }).click();

  await expect(page).toHaveURL(/\/obras\/[0-9a-f-]{36}$/);
  urlObra = new URL(page.url()).pathname;
  await expect(page.getByRole("heading", { name: obra })).toBeVisible();
  const contacto = page.getByRole("listitem").filter({ hasText: marta });
  await expect(contacto).toContainText("Referente");

  // Suma a Pedro.
  await page.getByRole("button", { name: "Sumar participante" }).click();
  const sumar = await panel(page);
  await sumar.getByLabel("Quién").selectOption({ label: "Tester 2" });
  await sumar.getByRole("button", { name: "Sumar", exact: true }).click();
  await expect(page.getByRole("listitem").filter({ hasText: "Tester 2" })).toBeVisible();

  // Cambia el estado.
  await page.getByRole("button", { name: "Idea" }).click();
  const estado = await panel(page);
  await estado.getByLabel("Pasa a").selectOption({ label: "En búsqueda" });
  await estado.getByRole("button", { name: "Cambiar" }).click();
  await expect(page.getByRole("button", { name: "En búsqueda" })).toBeVisible();

  // Vincula una constructora nueva desde el panel.
  await page.getByRole("button", { name: "Vincular contacto" }).click();
  const vincular = await panel(page);
  await vincular.getByRole("button", { name: "Constructora" }).click();
  await vincular.getByLabel("Buscar persona o empresa").fill(constructora);
  await vincular.getByRole("button", { name: `Crear «${constructora}» como empresa` }).click();
  await vincular.getByRole("button", { name: "Crear y vincular" }).click();
  await expect(page.getByRole("listitem").filter({ hasText: constructora })).toContainText("Constructora");

  // El teléfono de Marta, con "Ver contacto".
  await contacto.getByRole("link", { name: marta }).click();
  await expect(page.getByRole("heading", { name: marta })).toBeVisible();
  await page.getByRole("button", { name: "Ver contacto" }).click();
  await expect(page.getByRole("link", { name: "1155551234" })).toBeVisible();
  await expect(page.getByRole("link", { name: obra })).toBeVisible();

  await ctx.close();
});

test("el admin la ve con sus contactos y participantes", async ({ browser }) => {
  expect(urlObra).not.toBe("");
  const ctx = await browser.newContext({ storageState: "e2e/.auth/admin.json" });
  const page = await ctx.newPage();

  await page.goto("/obras/todas");
  await page.getByLabel("Buscar por nombre o dirección…").fill(marca);
  await page.getByLabel("Filtrar por estado").selectOption({ label: "Todas" });
  await page.getByRole("link", { name: new RegExp(obra) }).click();

  await expect(page).toHaveURL(new RegExp(`${urlObra}$`));
  await expect(page.getByRole("heading", { name: obra })).toBeVisible();
  await expect(page.getByRole("listitem").filter({ hasText: marta })).toContainText("Referente");
  await expect(page.getByRole("listitem").filter({ hasText: constructora })).toBeVisible();
  await expect(page.getByRole("listitem").filter({ hasText: "Tester 2" })).toBeVisible();

  await ctx.close();
});
