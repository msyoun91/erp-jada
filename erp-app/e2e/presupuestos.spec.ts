import { test, expect } from "@playwright/test";
import { como, panel, tarjeta } from "./comun";

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

// Necesita el paquete y el servicio de e2e/datos-opcionales.sql.
test("admin elige cómo se ven los opcionales y los tilda en cada ventana", async ({ browser }) => {
  test.setTimeout(180_000);
  const ctx = await browser.newContext({ storageState: "e2e/.auth/admin.json" });
  const page = await ctx.newPage();

  await page.goto("/presupuestos");
  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  await alta.getByLabel("Obra").selectOption({ index: 1 });
  await alta.getByLabel("Nombre", { exact: true }).fill(`Opcionales ${marca}`);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  await page.getByRole("link", { name: /Versión 1/ }).click();
  const general = page.getByRole("region", { name: "General" });

  await page.getByRole("button", { name: "Nueva sección" }).click();
  const nueva = panel(page);
  await nueva.getByLabel("Nombre").fill("Colocación");
  await nueva.getByLabel("IVA").selectOption("10.5");
  await nueva.getByRole("button", { name: "Crear sección" }).click();
  const colocacion = page.getByRole("region", { name: "Colocación" });
  await expect(colocacion).toBeVisible();

  await general.getByRole("button", { name: "De Catálogo" }).click();
  const cat = panel(page);
  await cat.getByLabel("Designación").fill("V1");
  await cat.getByLabel("Paquete").selectOption({ label: "Zqx197 Ventana opcionales" });
  await cat.getByLabel(/^ancho/).fill("1200");
  await cat.getByLabel(/^alto/).fill("1000");
  await cat.getByRole("button", { name: "Agregar" }).click();
  await expect(cat).toBeHidden();

  // En el precio, cada opcional es un botón.
  const v1 = general.getByRole("listitem").filter({ hasText: "V1" });
  const opcionales = v1.getByRole("group", { name: "Opcionales" });
  await expect(opcionales.getByRole("button", { name: "Mosquitero" })).toHaveAttribute("aria-pressed", "false");
  await expect(opcionales.getByRole("button", { name: "Zqx197 Colocación" })).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-opcionales-precio.png", fullPage: true });

  await page.getByRole("button", { name: "Más acciones" }).first().click();
  await page.getByRole("button", { name: "Cómo se ven los opcionales…" }).click();
  const como = panel(page);
  await como.getByLabel("Mosquitero").selectOption("debajo");
  await como.getByLabel("Zqx197 Colocación").selectOption({ label: "Colocación · ARS · IVA 10,5 %" });
  await page.screenshot({ path: "e2e/.out/pres-opcionales-panel.png", fullPage: true });
  await como.getByRole("button", { name: "Guardar" }).click();
  await expect(como).toBeHidden();

  // Debajo, la línea es la casilla: sin elegir, sin monto.
  const mosquitero = opcionales.getByRole("checkbox", { name: "Mosquitero" });
  await expect(mosquitero).not.toBeChecked();
  await mosquitero.check();
  await expect(opcionales.getByText("$9.600")).toBeVisible();

  // La Cortina lleva el Cajón.
  await opcionales.getByRole("button", { name: "Cortina" }).click();
  await expect(page.getByText("Cortina lleva Cajón.")).toBeVisible();
  await expect(opcionales.getByRole("button", { name: "Cajón" })).toHaveAttribute("aria-pressed", "true");
  await expect(opcionales.getByRole("button", { name: "Cortina" })).toHaveAttribute("aria-pressed", "true");

  // Aparte: un renglón en su sección, que no se saca mientras lo tenga.
  await opcionales.getByRole("button", { name: "Zqx197 Colocación" }).click();
  const aparte = colocacion.getByRole("listitem").filter({ hasText: "Zqx197 Colocación" });
  await expect(aparte.getByText("De 1 ventana")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-opcionales-elegidos.png", fullPage: true });
  await colocacion.getByRole("button", { name: "Más acciones" }).click();
  await expect(page.getByRole("button", { name: "Sacar" })).toHaveCount(0);
  await page.keyboard.press("Escape");

  await page.getByRole("button", { name: "Más acciones" }).first().click();
  await page.getByRole("button", { name: "Cómo se ven los opcionales…" }).click();
  const vuelta = panel(page);
  await vuelta.getByLabel("Zqx197 Colocación").selectOption("precio");
  await vuelta.getByRole("button", { name: "Guardar" }).click();
  await expect(aparte).toHaveCount(0);
  await expect(opcionales.getByRole("button", { name: "Zqx197 Colocación" })).toHaveAttribute("aria-pressed", "true");

  await mosquitero.uncheck();
  await expect(opcionales.getByText("$9.600")).toHaveCount(0);
  await ctx.close();
});

// Necesita e2e/datos-autorizaciones.sql: tope 10 %, Tester arma sin autorizar y Admin autoriza. La obra no puede estar
// congelada: publicar la mueve a cotización (OB018).
test("tester pide, retira y publica; admin devuelve y autoriza", async ({ browser }) => {
  test.setTimeout(240_000);
  const vendedor = await como(browser, "tester");
  const jefe = await como(browser, "admin");
  const page = vendedor.page;
  const nombreAut = `Autorizar ${marca}`;
  const confirmar = (p: typeof page, boton: string) => p.getByRole("dialog").getByRole("button", { name: boton }).click();

  await page.goto("/presupuestos");
  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  await alta.getByLabel("Obra").selectOption({ label: "Edificio Norte Zqx20218 A" });
  await alta.getByLabel("Nombre", { exact: true }).fill(nombreAut);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  await page.getByRole("link", { name: /Versión 1/ }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}\/[0-9a-f-]{36}$/);
  const url = page.url();

  const antes = page.getByRole("region", { name: "Antes de publicar" });
  await expect(antes.getByText("La versión no tiene renglones")).toBeVisible();
  await expect(antes.getByRole("button", { name: "Publicar" })).toBeDisabled();

  // A mano no pide nada; el descuento sobre el tope, al jefe.
  await page.getByRole("region", { name: "General" }).getByRole("button", { name: "A mano" }).click();
  const mano = panel(page);
  await mano.getByLabel("Descripción").fill("Flete cerrado a Pilar");
  await mano.getByLabel(/Precio por unidad/).fill("150000");
  await mano.getByRole("button", { name: "Agregar" }).click();
  await expect(mano).toBeHidden();
  await expect(antes.getByText("Nada pide autorización: se puede publicar.")).toBeVisible();
  await page.getByRole("button", { name: "Editar" }).click();
  const datos = panel(page);
  await datos.getByLabel("Descuento").fill("15");
  await datos.getByRole("button", { name: "Guardar" }).click();
  await expect(datos).toBeHidden();
  const delJefe = antes.getByRole("listitem").filter({ hasText: "Del jefe comercial" });
  await expect(delJefe.getByText("Falta pedirla")).toBeVisible();
  await expect(delJefe.getByText("Descuento de 15 %, sobre el tope de 10 %")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-antes-borrador.png", fullPage: true });

  await antes.getByRole("button", { name: "Pedir autorización" }).click();
  await confirmar(page, "Pedir");
  await expect(delJefe.getByText("Pendiente")).toBeVisible();
  await expect(page.getByText("En revisión", { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Editar" })).toHaveCount(0);
  await expect(antes.getByRole("button", { name: "Publicar" })).toBeDisabled();
  await page.screenshot({ path: "e2e/.out/pres-antes-revision.png", fullPage: true });

  await antes.getByRole("button", { name: "Retirar de revisión" }).click();
  await confirmar(page, "Retirar");
  await expect(delJefe.getByText("Falta pedirla")).toBeVisible();
  await antes.getByRole("button", { name: "Pedir autorización" }).click();
  await confirmar(page, "Pedir");
  await expect(delJefe.getByText("Pendiente")).toBeVisible();

  // El jefe la encuentra en su filtro y la devuelve.
  const j = jefe.page;
  await j.goto("/presupuestos");
  await j.getByRole("button", { name: /Esperan mi autorización/ }).click();
  await j.getByRole("link", { name: new RegExp(nombreAut) }).click();
  await expect(j).toHaveURL(url);
  const antesJefe = j.getByRole("region", { name: "Antes de publicar" });
  await expect(antesJefe.getByText("Pedida por Tester")).toBeVisible();
  await j.screenshot({ path: "e2e/.out/pres-antes-jefe.png", fullPage: true });
  await antesJefe.getByRole("button", { name: "Devolver" }).click();
  const devolver = panel(j);
  await devolver.getByRole("button", { name: "Devolver" }).click();
  await expect(devolver.getByText("Escribí el motivo")).toBeVisible();
  await devolver.getByLabel("Motivo").fill("El descuento va hasta 12 %");
  await devolver.getByRole("button", { name: "Devolver" }).click();
  await expect(devolver).toBeHidden();
  await expect(antesJefe.getByText("Devuelta por vos")).toBeVisible();

  // Quien armó ve el motivo, corrige y pide de nuevo.
  // El nombre de quien resolvió sale de `obras_nombres`: Admin está solo si actuó en la obra.
  await page.reload();
  await expect(antes.getByText(/^Devuelta( por Admin)? el/)).toBeVisible();
  await expect(antes.getByText("El descuento va hasta 12 %")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-antes-devuelta.png", fullPage: true });
  await page.getByRole("button", { name: "Editar" }).click();
  const corregir = panel(page);
  await corregir.getByLabel("Descuento").fill("12");
  await corregir.getByRole("button", { name: "Guardar" }).click();
  await expect(corregir).toBeHidden();
  await antes.getByRole("button", { name: "Pedir autorización" }).click();
  await confirmar(page, "Pedir");
  await expect(delJefe.getByText("Pendiente")).toBeVisible();

  await j.reload();
  await antesJefe.getByRole("button", { name: "Autorizar" }).click();
  await confirmar(j, "Autorizar");
  await expect(antesJefe.getByText("Autorizada por vos")).toBeVisible();
  await expect(antesJefe.getByText("Autorizaron todo: lista para publicar.")).toBeVisible();

  // Publica quien armó.
  await page.reload();
  await expect(delJefe.getByText(/^Autorizada( por Admin)? el/)).toBeVisible();
  await antes.getByRole("button", { name: "Publicar" }).click();
  await expect(page.getByRole("dialog").getByText("vence en 15 días")).toBeVisible();
  await confirmar(page, "Publicar");
  await expect(page.getByText("Publicada", { exact: true })).toBeVisible();
  await expect(antes).toHaveCount(0);
  await expect(page.getByText(/Vence el/)).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-antes-publicada.png", fullPage: true });

  await vendedor.ctx.close();
  await jefe.ctx.close();
});

// Necesita e2e/datos-mantener.sql (y antes datos-opcionales.sql): la variante 2, copiada de la 1, en borrador. Arranca y
// termina con todo a hoy, así se puede correr de nuevo.
test("admin mantiene o pasa a hoy cada ventana copiada, y todas juntas", async ({ browser }) => {
  test.setTimeout(180_000);
  const { ctx, page } = await como(browser, "admin");
  const confirmar = (boton: string) => page.getByRole("dialog").getByRole("button", { name: boton }).click();

  await page.goto("/presupuestos");
  await page.getByRole("link", { name: /Mantener Zqx198/ }).click();
  await page.getByRole("link", { name: /Versión 2/ }).click();
  const version = tarjeta(page, "Versión 2");
  await expect(version).toBeVisible();
  const v1 = page.getByRole("region", { name: "General" }).getByRole("listitem").filter({ hasText: "V1" }).first();
  const antes = page.getByRole("region", { name: "Antes de publicar" });
  const delJefe = antes.getByRole("listitem").filter({ hasText: "Del jefe comercial" });
  const todasAHoy = async () => {
    await version.getByRole("button", { name: "Más acciones" }).click();
    await page.getByRole("button", { name: "Todas a hoy…" }).click();
    await expect(page.getByRole("dialog").getByText("Las ventanas y los mínimos se recalculan")).toBeVisible();
    await confirmar("Pasar a hoy");
    await expect(page.getByText(/^Precios del/)).toHaveCount(0);
    await expect(delJefe).toHaveCount(0);
  };

  await todasAHoy();

  // Una por una: mantener pide autorización del jefe, aunque el precio no cambie.
  await v1.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: /^Mantener precios del/ }).click();
  await expect(v1.getByText(/^Precios del/)).toBeVisible();
  await expect(delJefe.getByText("1 renglón mantenido")).toBeVisible();
  await expect(delJefe.getByText("Falta pedirla")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-mantener-una.png", fullPage: true });
  await v1.getByRole("button", { name: "Más acciones" }).click();
  await expect(page.getByRole("button", { name: "Actualizar a hoy" })).toHaveCount(0);
  await page.getByRole("button", { name: "Pasar a hoy" }).click();
  await expect(v1.getByText(/^Precios del/)).toHaveCount(0);
  await expect(delJefe).toHaveCount(0);

  // Todas juntas, y de vuelta a hoy.
  await version.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Mantener todas…" }).click();
  await expect(page.getByRole("dialog").getByText(/Los 2 renglones copiados vuelven/)).toBeVisible();
  await confirmar("Mantener");
  await expect(page.getByText(/^Precios del/)).toHaveCount(2);
  await expect(delJefe.getByText("2 renglones mantenidos")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-mantener-todas.png", fullPage: true });
  await version.getByRole("button", { name: "Más acciones" }).click();
  await expect(page.getByRole("button", { name: "Mantener todas…" })).toHaveCount(0);
  await page.keyboard.press("Escape");
  await todasAHoy();

  await ctx.close();
});

// Necesita e2e/datos-autorizaciones.sql (tope y plazo). Publicar mueve la obra a cotización: no puede estar congelada (OB018).
test("admin renombra, corrige, descarta, suma una variante y la quita", async ({ browser }) => {
  test.setTimeout(240_000);
  const { ctx, page } = await como(browser, "admin");
  const confirmar = (boton: string) => page.getByRole("dialog").getByRole("button", { name: boton }).click();
  const menu = async (card: ReturnType<typeof tarjeta>, accion: string | RegExp) => {
    await card.getByRole("button", { name: "Más acciones" }).click();
    await page.getByRole("button", { name: accion }).click();
  };
  const publicar = async () => {
    const antes = page.getByRole("region", { name: "Antes de publicar" });
    await antes.getByRole("button", { name: "Publicar" }).click();
    await confirmar("Publicar");
    await expect(page.getByText("Publicada", { exact: true })).toBeVisible();
  };

  await page.goto("/presupuestos");
  await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
  const alta = panel(page);
  await alta.getByLabel("Obra").selectOption({ label: "Edificio Norte Zqx20218 A" });
  await alta.getByLabel("Nombre", { exact: true }).fill(`Ficha ${marca}`);
  await alta.getByRole("button", { name: "Crear presupuesto" }).click();
  await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
  const ficha = page.url();

  await page.getByRole("button", { name: "Editar" }).click();
  const datos = panel(page);
  await datos.getByLabel("Nombre").fill(`Ficha ${marca} Belgrano`);
  await datos.getByRole("button", { name: "Guardar" }).click();
  await expect(page.getByRole("heading", { name: new RegExp(`Ficha ${marca} Belgrano`) })).toBeVisible();

  // Un borrador solo no se corrige ni se descarta.
  const unica = tarjeta(page, "Presupuesto");
  await expect(unica.getByRole("button", { name: "Corregir" })).toHaveCount(0);
  await unica.getByRole("button", { name: "Más acciones" }).click();
  await expect(page.getByRole("button", { name: /^Descartar/ })).toHaveCount(0);
  await page.keyboard.press("Escape");

  await page.getByRole("link", { name: /Versión 1/ }).click();
  await page.getByRole("region", { name: "General" }).getByRole("button", { name: "A mano" }).click();
  const mano = panel(page);
  await mano.getByLabel("Descripción").fill("Flete cerrado a Pilar");
  await mano.getByLabel(/Precio por unidad/).fill("150000");
  await mano.getByRole("button", { name: "Agregar" }).click();
  await expect(mano).toBeHidden();
  await publicar();

  // Corregir abre la versión 2 en borrador; descartarla deja de nuevo la publicada sola.
  await page.goto(ficha);
  await unica.getByRole("button", { name: "Corregir" }).click();
  await expect(page.getByRole("heading", { name: "Versión 2" })).toBeVisible();
  await expect(page.getByText("Borrador", { exact: true })).toBeVisible();
  await page.goto(ficha);
  await expect(unica.getByRole("button", { name: "Corregir" })).toHaveCount(0);
  await page.screenshot({ path: "e2e/.out/pres-ficha-corrigiendo.png", fullPage: true });
  await menu(unica, "Descartar la versión 2…");
  await expect(page.getByRole("dialog").getByText("El cliente sigue viendo la publicada")).toBeVisible();
  await confirmar("Descartar");
  await expect(page.getByRole("link", { name: /Versión 2/ })).toHaveCount(0);
  await expect(unica.getByRole("button", { name: "Corregir" })).toBeVisible();

  // Sumar variante copia la publicada; se publica con nombre, y con dos publicadas una se quita.
  await menu(unica, "Sumar variante a partir de esta");
  await expect(page.getByRole("heading", { name: "Versión 3" })).toBeVisible();
  await expect(page.getByRole("region", { name: "General" }).getByText("Flete cerrado a Pilar")).toBeVisible();
  await page.getByRole("button", { name: "Editar" }).click();
  const variante = panel(page);
  await variante.getByLabel("Nombre de la variante").fill("PVC");
  await variante.getByRole("button", { name: "Guardar" }).click();
  await expect(variante).toBeHidden();
  await publicar();

  await page.goto(ficha);
  const pvc = tarjeta(page, "PVC");
  await expect(tarjeta(page, "Variante 1")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-ficha-variantes.png", fullPage: true });
  await menu(pvc, "Quitar variante…");
  await expect(page.getByRole("dialog").getByText(/^PVC deja de ofrecerse/)).toBeVisible();
  await confirmar("Quitar");
  await expect(pvc.getByText("Quitada", { exact: true })).toBeVisible();
  await expect(pvc.getByRole("button", { name: "Corregir" })).toHaveCount(0);
  await tarjeta(page, "Variante 1").getByRole("button", { name: "Más acciones" }).click();
  await expect(page.getByRole("button", { name: "Quitar variante…" })).toHaveCount(0);
  await page.keyboard.press("Escape");
  await page.screenshot({ path: "e2e/.out/pres-ficha-quitada.png", fullPage: true });

  await ctx.close();
});

// Necesita e2e/datos-autorizaciones.sql (tope y plazo). Aprobar y revertir mueven la obra: no puede estar congelada (OB018).
// Termina publicado, así la obra queda como estaba.
test("admin aprueba, rechaza y revierte; tester no revierte; un borrador se desactiva", async ({ browser }) => {
  test.setTimeout(300_000);
  const { ctx, page } = await como(browser, "admin");
  const vendedor = await como(browser, "tester");
  const dialogo = page.getByRole("dialog");
  const cabecera = page.locator("div.card").first();
  const nuevo = async (nombrePres: string) => {
    await page.goto("/presupuestos");
    await page.getByRole("button", { name: "Nuevo presupuesto" }).click();
    const alta = panel(page);
    await alta.getByLabel("Obra").selectOption({ label: "Edificio Norte Zqx20218 A" });
    await alta.getByLabel("Nombre", { exact: true }).fill(nombrePres);
    await alta.getByRole("button", { name: "Crear presupuesto" }).click();
    await expect(page).toHaveURL(/\/presupuestos\/[0-9a-f-]{36}$/);
    return page.url();
  };
  const publicar = async () => {
    const antes = page.getByRole("region", { name: "Antes de publicar" });
    await antes.getByRole("button", { name: "Publicar" }).click();
    await dialogo.getByRole("button", { name: "Publicar" }).click();
    await expect(page.getByText("Publicada", { exact: true })).toBeVisible();
  };
  const revertir = async (titulo: string, causa: string) => {
    await cabecera.getByRole("button", { name: "Más acciones" }).click();
    await page.getByRole("button", { name: "Revertir…" }).click();
    await expect(dialogo.getByRole("heading", { name: titulo })).toBeVisible();
    await dialogo.getByLabel("Por qué se revierte").fill(causa);
    await dialogo.getByRole("button", { name: "Revertir" }).click();
    await expect(dialogo).toBeHidden();
    await expect(cabecera.getByText("Publicado", { exact: true })).toBeVisible();
  };

  // Dos variantes publicadas y una corrección abierta.
  const ficha = await nuevo(`Aprobar ${marca}`);
  await expect(page.getByRole("button", { name: "Aprobar" })).toHaveCount(0);
  await page.getByRole("link", { name: /Versión 1/ }).click();
  await page.getByRole("region", { name: "General" }).getByRole("button", { name: "A mano" }).click();
  const mano = panel(page);
  await mano.getByLabel("Descripción").fill("Flete cerrado a Pilar");
  await mano.getByLabel(/Precio por unidad/).fill("150000");
  await mano.getByRole("button", { name: "Agregar" }).click();
  await expect(mano).toBeHidden();
  await publicar();
  await page.goto(ficha);
  await tarjeta(page, "Presupuesto").getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Sumar variante a partir de esta" }).click();
  await expect(page.getByRole("heading", { name: "Versión 2" })).toBeVisible();
  await page.getByRole("button", { name: "Editar" }).click();
  const variante = panel(page);
  await variante.getByLabel("Nombre de la variante").fill("PVC");
  await variante.getByRole("button", { name: "Guardar" }).click();
  await expect(variante).toBeHidden();
  await publicar();
  await page.goto(ficha);
  await tarjeta(page, "Variante 1").getByRole("button", { name: "Corregir" }).click();
  await expect(page.getByRole("heading", { name: "Versión 3" })).toBeVisible();

  // Aprobar pide la variante, inhabilita la otra y descarta la abierta.
  await page.goto(ficha);
  await cabecera.getByRole("button", { name: "Aprobar" }).click();
  await expect(dialogo.getByText("La versión 3, sin publicar, se descarta.", { exact: false })).toBeVisible();
  await dialogo.getByRole("button", { name: "Aprobar" }).click();
  await expect(dialogo.getByText("Elegí la variante que aprobó el cliente")).toBeVisible();
  await dialogo.getByRole("radio", { name: /^PVC/ }).check();
  await page.screenshot({ path: "e2e/.out/pres-aprobar.png", fullPage: true });
  await dialogo.getByRole("button", { name: "Aprobar" }).click();
  await expect(dialogo).toBeHidden();
  await expect(cabecera.getByText("Aprobado", { exact: true })).toBeVisible();
  await expect(tarjeta(page, "PVC").getByText("Aprobada", { exact: true })).toBeVisible();
  await expect(tarjeta(page, "Variante 1").getByText("Inhabilitada", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: /Versión 3/ })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Editar" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Corregir" })).toHaveCount(0);
  await page.screenshot({ path: "e2e/.out/pres-aprobado.png", fullPage: true });

  // Revierte quien autoriza: Tester arma, pero no autoriza.
  await vendedor.page.goto(ficha);
  await expect(vendedor.page.getByText("Aprobado", { exact: true })).toBeVisible();
  await expect(vendedor.page.locator("div.card").getByRole("button", { name: "Más acciones" })).toHaveCount(0);

  await cabecera.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Revertir…" }).click();
  await dialogo.getByRole("button", { name: "Revertir" }).click();
  await expect(dialogo.getByText("Escribí por qué se revierte")).toBeVisible();
  await dialogo.getByRole("button", { name: "Volver" }).click();
  await revertir("Revertir la aprobación", "Se aprobó PVC y el cliente eligió Aluminio");
  await expect(cabecera.getByText("Se aprobó PVC y el cliente eligió Aluminio")).toBeVisible();
  await expect(tarjeta(page, "PVC").getByText("Publicada", { exact: true })).toBeVisible();

  // Rechazar pide motivo, y con "Otro", el detalle.
  await cabecera.getByRole("button", { name: "Rechazar" }).click();
  await dialogo.getByLabel("Motivo").selectOption({ label: "Otro" });
  await dialogo.getByRole("button", { name: "Rechazar" }).click();
  await expect(dialogo.getByText("Contá qué pasó")).toBeVisible();
  await dialogo.getByLabel("Motivo").selectOption({ label: "Precio" });
  await dialogo.getByLabel("Detalle").fill("Estuvimos 10% más caros");
  await dialogo.getByRole("button", { name: "Rechazar" }).click();
  await expect(dialogo).toBeHidden();
  await expect(cabecera.getByText("Rechazado", { exact: true })).toBeVisible();
  await expect(cabecera.getByText("Precio.")).toBeVisible();
  await expect(cabecera.getByText("Estuvimos 10% más caros")).toBeVisible();
  await page.screenshot({ path: "e2e/.out/pres-rechazado.png", fullPage: true });
  await revertir("Revertir el rechazo", "Se registró en el presupuesto equivocado");

  // Un borrador se desactiva y sale de la lista.
  await nuevo(`Desactivar ${marca}`);
  await cabecera.getByRole("button", { name: "Más acciones" }).click();
  await page.getByRole("button", { name: "Desactivar…" }).click();
  await dialogo.getByRole("button", { name: "Desactivar" }).click();
  await expect(page).toHaveURL(/\/presupuestos$/);
  await expect(page.getByText(`Desactivar ${marca}`)).toHaveCount(0);

  await vendedor.ctx.close();
  await ctx.close();
});
