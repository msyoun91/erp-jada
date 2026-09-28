import { test, expect, type Page } from "@playwright/test";
import { aprobarPendientes, como, crearIgual, panel } from "./comun";

// Tramo 3: compartir empresa. Caputo es de "Equipo Zqx pruebas" (Norte, el de
// Pedro); el admin la comparte con "Equipo Zqx sur", donde está Juan (tester),
// que la ve en su lista como compartida y no la comparte él. Al dejar de
// compartir, Juan deja de verla. Juan sale de Sur al final: `obras.spec.ts` lo
// suma a Norte.
const marca = `Zqx${Date.now() % 100000}`;
const caputo = `Constructora Caputo ${marca}`;
const norte = "Equipo Zqx pruebas";
const sur = "Equipo Zqx sur";

function seccion(page: Page, equipo: string) {
  return page.locator("section").filter({ has: page.getByRole("heading", { name: equipo }) });
}

async function asegurarEquipo(page: Page, equipo: string) {
  await page.goto("/usuarios/equipos");
  await expect(page.getByRole("button", { name: "Nuevo equipo" })).toBeVisible();
  if ((await seccion(page, equipo).count()) > 0) return;
  await page.getByRole("button", { name: "Nuevo equipo" }).click();
  const alta = panel(page);
  await alta.getByLabel("Nombre").fill(equipo);
  await alta.getByRole("button", { name: "Crear equipo" }).click();
  await expect(seccion(page, equipo)).toBeVisible();
}

test("Norte comparte Caputo con Sur y deja de compartirla", async ({ browser }) => {
  test.setTimeout(120_000);
  const { ctx: ctxAdmin, page: admin } = await como(browser, "admin");
  await asegurarEquipo(admin, norte);
  await asegurarEquipo(admin, sur);
  const deSur = seccion(admin, sur);
  if ((await deSur.getByText("Tester", { exact: true }).count()) === 0) {
    await deSur.locator("header").getByRole("button", { name: "Más acciones" }).click();
    await admin.getByRole("button", { name: "Agregar miembro" }).click();
    const alta = panel(admin);
    await alta.getByLabel("Usuario").selectOption({ label: "Tester" });
    await alta.getByRole("button", { name: "Agregar" }).click();
    await expect(deSur.getByText("Tester", { exact: true })).toBeVisible();
  }

  try {
    // El admin carga Caputo y se la pasa a Norte.
    await admin.goto("/contactos/empresas");
    await admin.getByRole("button", { name: "Nueva empresa" }).click();
    const alta = panel(admin);
    await alta.getByLabel("Nombre").fill(caputo);
    const url = await crearIgual(admin, alta, "Crear empresa", /\/contactos\/empresas\/[0-9a-f-]{36}$/);
    await admin.getByRole("button", { name: "Más acciones" }).click();
    await admin.getByRole("button", { name: "Asignar equipo" }).click();
    const equipo = panel(admin);
    await equipo.getByLabel("Equipo").selectOption({ label: norte });
    await equipo.getByRole("button", { name: "Guardar" }).click();
    await expect(admin.getByTitle("Equipo")).toHaveText(norte);

    const { ctx: ctxJuan, page: juan } = await como(browser, "tester");
    await juan.goto("/contactos/empresas");
    await expect(juan.getByRole("button", { name: "Nueva empresa" })).toBeVisible();
    await expect(juan.getByRole("link", { name: caputo })).toHaveCount(0);

    // Compartir: Sur aparece en la ficha y ya no se ofrece.
    await admin.getByRole("button", { name: "Más acciones" }).click();
    await admin.getByRole("button", { name: "Compartir con otro equipo" }).click();
    const compartir = panel(admin);
    await expect(compartir.getByRole("option", { name: norte })).toHaveCount(0);
    await compartir.getByLabel("Equipo").selectOption({ label: sur });
    await compartir.getByRole("button", { name: "Compartir" }).click();
    await expect(compartir).toBeHidden();
    await expect(admin.getByText("Compartida con")).toBeVisible();
    await expect(admin.getByRole("button", { name: `Dejar de compartir con ${sur}` })).toBeVisible();

    // Juan la ve en su lista, marcada, y en la ficha no la comparte.
    await juan.reload();
    const fila = juan.getByRole("link", { name: caputo });
    await expect(fila.getByText(`Compartida por ${norte}`)).toBeVisible();
    await fila.click();
    await expect(juan.getByRole("heading", { name: caputo })).toBeVisible();
    await expect(juan.getByText("Compartida con")).toBeVisible();
    await expect(juan.getByRole("button", { name: `Dejar de compartir con ${sur}` })).toHaveCount(0);
    await juan.getByRole("button", { name: "Más acciones" }).click();
    await expect(juan.getByRole("button", { name: "Editar" })).toBeVisible();
    await expect(juan.getByRole("button", { name: "Compartir con otro equipo" })).toHaveCount(0);
    await juan.keyboard.press("Escape");

    // Dejar de compartir: Juan deja de verla.
    await admin.getByRole("button", { name: `Dejar de compartir con ${sur}` }).click();
    await panel(admin).getByRole("button", { name: "Dejar de compartir" }).click();
    await expect(admin.getByText("Compartida con")).toHaveCount(0);

    await juan.goto("/contactos/empresas");
    await expect(juan.getByRole("button", { name: "Nueva empresa" })).toBeVisible();
    await expect(juan.getByRole("link", { name: caputo })).toHaveCount(0);
    await juan.goto(url);
    await expect(juan.getByRole("heading", { name: caputo })).toHaveCount(0);
    await ctxJuan.close();
  } finally {
    await admin.goto("/usuarios/equipos");
    await expect(deSur.getByText("Tester", { exact: true })).toBeVisible();
    const fila = deSur.locator("div.row").filter({ has: admin.getByText("Tester", { exact: true }) });
    await fila.getByRole("button", { name: "Más acciones" }).click();
    await admin.getByRole("button", { name: "Sacar del equipo" }).click();
    const sacar = panel(admin);
    await sacar.getByRole("checkbox", { name: /Su agenda pasa al jefe/ }).uncheck();
    await sacar.getByRole("button", { name: "Sacar" }).click();
    await expect(deSur.getByText("Tester", { exact: true })).toHaveCount(0);
    await ctxAdmin.close();
  }
});

// Tramo 4: Auditoría. Tester mira el contacto de una persona suya y el admin
// la mira sin ser suya; el admin, con "Auditoría", ve los dos accesos y cuál
// no era suyo. Tester no tiene la vista.
test("El auditor ve quién miró a Marta y que no era suya", async ({ browser }) => {
  test.setTimeout(120_000);
  const marta = `Marta Auditada ${marca}`;
  const { ctx: ctxAdmin, page: admin } = await como(browser, "admin");

  await admin.goto("/usuarios");
  const fila = admin.locator("div.row").filter({ has: admin.getByText("Admin", { exact: true }) });
  await fila.getByRole("button", { name: "Más acciones" }).click();
  await admin.getByRole("button", { name: "Permisos" }).click();
  const permisos = panel(admin);
  const bloque = permisos.locator("div.border-b").filter({ has: admin.getByText("Contactos", { exact: true }) });
  const casilla = bloque.getByRole("checkbox", { name: /^Auditoría/ });
  const tenia = await casilla.isChecked();
  if (!tenia) await casilla.check();
  await permisos.getByRole("button", { name: tenia ? "Cancelar" : "Guardar" }).click();
  await expect(permisos).toBeHidden();

  // Juan carga a Marta y mira su contacto.
  const { ctx: ctxJuan, page: juan } = await como(browser, "tester");
  await juan.goto("/contactos");
  await juan.getByRole("button", { name: "Nueva persona" }).click();
  const alta = panel(juan);
  await alta.getByLabel("Nombre").fill(marta);
  await alta.getByLabel("Teléfono").fill("1144556677");
  const url = await crearIgual(juan, alta, "Crear persona", /\/contactos\/personas\/[0-9a-f-]{36}$/);
  await juan.getByRole("button", { name: "Ver contacto" }).click();
  await expect(juan.getByText("1144556677")).toBeVisible();
  await expect(juan.getByRole("link", { name: "Auditoría" })).toHaveCount(0);
  await juan.goto("/contactos/auditoria");
  await expect(juan.getByRole("heading", { name: "Quién miró contactos" })).toHaveCount(0);
  await ctxJuan.close();

  // El admin la mira sin ser suya.
  await admin.goto(url);
  await admin.getByRole("button", { name: "Ver contacto" }).click();
  await expect(admin.getByText("1144556677")).toBeVisible();

  // Auditoría, filtrada por Marta: los dos accesos, el del admin marcado.
  await admin.getByRole("link", { name: "Auditoría" }).click();
  await expect(admin.getByRole("heading", { name: "Quién miró contactos" })).toBeVisible();
  await admin.getByRole("button", { name: "Filtrar por persona" }).click();
  await admin.getByPlaceholder("Buscar persona").fill(marta);
  await admin.getByRole("button", { name: marta }).click();
  await expect(admin.getByRole("heading", { name: `Quién miró a ${marta}` })).toBeVisible();
  const detalle = admin.locator("section").filter({ has: admin.getByRole("heading", { name: `Quién miró a ${marta}` }) });
  const deAdmin = detalle.locator("li").filter({ has: admin.getByText("Admin", { exact: true }) });
  const deJuan = detalle.locator("li").filter({ has: admin.getByText("Tester", { exact: true }) });
  await expect(deAdmin.getByText("No era suya")).toBeVisible();
  await expect(deAdmin.getByText("de Tester")).toBeVisible();
  await expect(deJuan.getByText("suya", { exact: false }).first()).toBeVisible();
  await expect(deJuan.getByText("No era suya")).toHaveCount(0);

  // Tocar un usuario suma su detalle; el período conserva los filtros.
  await admin.getByRole("link", { name: /^Admin/ }).click();
  await expect(admin.getByRole("heading", { name: `Admin y ${marta}` })).toBeVisible();
  await admin.getByRole("link", { name: "7 días" }).click();
  await expect(admin).toHaveURL(/usuario=.*persona=.*dias=7|dias=7.*usuario=/);
  await expect(admin.getByRole("heading", { name: `Admin y ${marta}` })).toBeVisible();
  await ctxAdmin.close();
});

// Tramo 4: fusionar. Juan carga a Marta dos veces, una con teléfono y otra con
// email; el admin las fusiona desde la ficha de la primera, que queda y toma
// el email de la otra. El link viejo muestra "Se fusionó con …" al admin y
// lleva a Juan, que ya no ve la que se fue, a la que queda.
test("El admin fusiona las dos Marta de Juan", async ({ browser }) => {
  test.setTimeout(180_000);
  const queda = `Marta Fusion ${marca}`;
  const seVa = `Marta Fusión ${marca}`;
  // Por corrida: con el mismo dato que una anterior, no se aprueba.
  const telefono = `11${marca.slice(3).padStart(8, "0")}`;
  const { ctx: ctxJuan, page: juan } = await como(browser, "tester");
  const urls: string[] = [];
  for (const [nombre, campo, valor] of [
    [queda, "Teléfono", telefono],
    [seVa, "Email", `marta.${marca.toLowerCase()}@zqx.test`],
  ]) {
    await juan.goto("/contactos");
    await juan.getByRole("button", { name: "Nueva persona" }).click();
    const alta = panel(juan);
    await alta.getByLabel("Nombre").fill(nombre);
    await alta.getByLabel(campo).fill(valor);
    urls.push(await crearIgual(juan, alta, "Crear persona", /\/contactos\/personas\/[0-9a-f-]{36}$/));
  }
  // La segunda se parece a la primera: queda por aprobar hasta que el admin la aprueba.
  await aprobarPendientes(browser, marca);

  const { ctx: ctxAdmin, page: admin } = await como(browser, "admin");
  await admin.goto(urls[0]);
  await admin.getByRole("button", { name: "Más acciones" }).click();
  await admin.getByRole("button", { name: "Fusionar con…" }).click();
  await panel(admin).getByPlaceholder("Buscar persona").fill(seVa);
  await panel(admin).getByRole("button", { name: seVa }).click();
  await expect(admin.getByRole("heading", { name: "Fusionar personas" })).toBeVisible();

  const fusionar = admin.getByRole("button", { name: "Fusionar", exact: true });
  await expect(fusionar).toBeDisabled();
  await admin.getByRole("button", { name: "Ver los de las dos" }).click();
  // Sin email en la que queda, se elige el de la otra.
  await expect(admin.getByRole("radio", { name: new RegExp(`^marta\\.${marca.toLowerCase()}@`) })).toBeChecked();
  await expect(admin.getByRole("radio", { name: new RegExp(`^${telefono}`) })).toBeChecked();
  await fusionar.click();
  await panel(admin).getByRole("button", { name: "Fusionar" }).click();
  await expect(admin).toHaveURL(new RegExp(`${urls[0]}$`));
  await admin.getByRole("button", { name: "Ver contacto" }).click();
  await expect(admin.getByText(`marta.${marca.toLowerCase()}@zqx.test`)).toBeVisible();
  await expect(admin.getByText(telefono)).toBeVisible();

  await admin.goto(urls[1]);
  await expect(admin.getByText("Desactivada")).toBeVisible();
  await admin.getByRole("link", { name: `${queda} (de Tester) →` }).click();
  await expect(admin).toHaveURL(new RegExp(`${urls[0]}$`));
  await ctxAdmin.close();

  await juan.goto(urls[1]);
  await expect(juan).toHaveURL(new RegExp(`${urls[0]}$`));
  await expect(juan.getByRole("heading", { name: queda })).toBeVisible();
  await ctxJuan.close();
});
