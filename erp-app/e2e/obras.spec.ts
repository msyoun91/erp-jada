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

// Tramo 2: Juan (tester) entra al equipo de Pedro (Tester 2, el jefe), carga una
// obra con una persona nueva y el admin lo saca con "su agenda pasa al jefe". El
// equipo es fijo: el delegador no sale, y uno por corrida dejaría a Pedro atrapado.
const equipo = "Equipo Zqx pruebas";
const obraDeJuan = `Casa Olivos ${marca}`;
const ana = `Ana Ruiz ${marca}`;

test("Juan se va y sus obras y su agenda llegan al jefe", async ({ browser }) => {
  test.setTimeout(120_000);
  const ctxAdmin = await browser.newContext({ storageState: "e2e/.auth/admin.json" });
  const admin = await ctxAdmin.newPage();
  await admin.goto("/usuarios/equipos");
  const seccion = admin.locator("section").filter({ has: admin.getByRole("heading", { name: equipo }) });

  async function menuDe(texto: string) {
    const fila = seccion.locator("div.row").filter({ has: admin.getByText(texto, { exact: true }) });
    await fila.getByRole("button", { name: "Más acciones" }).click();
  }
  async function agregar(nombre: string) {
    await seccion.locator("header").getByRole("button", { name: "Más acciones" }).click();
    await admin.getByRole("button", { name: "Agregar miembro" }).click();
    const alta = await panel(admin);
    await alta.getByLabel("Usuario").selectOption({ label: nombre });
    await alta.getByRole("button", { name: "Agregar" }).click();
    await expect(seccion.getByText(nombre, { exact: true })).toBeVisible();
  }

  async function darPermiso(nombre: string, permiso: RegExp) {
    await admin.goto("/usuarios");
    const fila = admin.locator("div.row").filter({ has: admin.getByText(nombre, { exact: true }) });
    await fila.getByRole("button", { name: "Más acciones" }).click();
    await admin.getByRole("button", { name: "Permisos" }).click();
    const permisos = await panel(admin);
    const casilla = permisos.getByRole("checkbox", { name: permiso });
    if (await casilla.isChecked()) {
      await permisos.getByRole("button", { name: "Cancelar" }).click();
      return;
    }
    await casilla.check();
    await permisos.getByRole("button", { name: "Guardar" }).click();
    await expect(permisos).toBeHidden();
  }

  if ((await seccion.count()) === 0) {
    await admin.getByRole("button", { name: "Nuevo equipo" }).click();
    const alta = await panel(admin);
    await alta.getByLabel("Nombre").fill(equipo);
    await alta.getByRole("button", { name: "Crear equipo" }).click();
    await expect(seccion).toBeVisible();
  }
  if ((await seccion.getByText("Tester 2", { exact: true }).count()) === 0) await agregar("Tester 2");
  // Pedro es el jefe comercial: delegador (que pide «Hilos» de Tareas) con
  // "Jefe de equipo" de Obras (decisiones/obras.md).
  await darPermiso("Tester 2", /^Hilos Vista/);
  await admin.goto("/usuarios/equipos");
  const delegador = seccion.getByText("Delegador", { exact: true });
  if ((await delegador.count()) === 0) {
    await menuDe("Tester 2");
    await admin.getByRole("button", { name: "Hacer delegador" }).click();
    await expect(delegador).toBeVisible();
  }
  await darPermiso("Tester 2", /^Jefe de equipo Función/);
  await admin.goto("/usuarios/equipos");

  // Una corrida que falló después de sumarlo lo deja adentro.
  if ((await seccion.getByText("Tester", { exact: true }).count()) === 0) await agregar("Tester");

  // Juan carga su obra con Ana, nueva en su agenda.
  const ctxJuan = await browser.newContext({ storageState: "e2e/.auth/tester.json" });
  const juan = await ctxJuan.newPage();
  await juan.goto("/obras");
  await juan.getByRole("button", { name: "Nueva obra" }).click();
  const alta = await panel(juan);
  await alta.getByLabel("Nombre", { exact: true }).fill(obraDeJuan);
  await alta.getByLabel("Dirección").fill("Av. Maipú 800");
  await alta.getByLabel("Tipo de obra").selectOption({ label: "Edificio residencial" });
  await alta.getByLabel("Origen").selectOption({ label: "Referente" });
  await alta.getByLabel("Buscar persona o empresa").fill(ana);
  await alta.getByRole("button", { name: `Crear «${ana}» como persona` }).click();
  await alta.getByRole("button", { name: "Crear obra" }).click();
  await expect(juan).toHaveURL(/\/obras\/[0-9a-f-]{36}$/);
  const urlObraDeJuan = new URL(juan.url()).pathname;
  await expect(juan.getByTitle("Responsable")).toHaveText("Vos");
  await ctxJuan.close();

  // El admin lo saca; la casilla viene marcada.
  await admin.reload();
  await menuDe("Tester");
  await admin.getByRole("button", { name: "Sacar del equipo" }).click();
  const sacar = await panel(admin);
  await expect(sacar.getByRole("checkbox", { name: /Su agenda pasa al jefe/ })).toBeChecked();
  await sacar.getByRole("button", { name: "Sacar" }).click();
  await expect(seccion.getByText("Tester", { exact: true })).toHaveCount(0);

  await admin.goto(urlObraDeJuan);
  await expect(admin.getByTitle("Responsable")).toHaveText("Tester 2");
  await admin.getByRole("listitem").filter({ hasText: ana }).getByRole("link", { name: ana }).click();
  await expect(admin.getByRole("heading", { name: ana })).toBeVisible();
  await expect(admin.getByTitle("Dueño")).toHaveText("Tester 2");

  await ctxAdmin.close();
});
