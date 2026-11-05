import { test, expect, type Browser, type Locator, type Page } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { como, panel } from "./comun";

process.loadEnvFile(".env.local");

// Las cuatro personas de la ficha (decisiones/catalogo/README.md), cada una con sus permisos y nada más.
// El paquete nace duplicando "Zqx501 Ciclo", publicado: pasa el ciclo entero sin armarlo desde cero.
const marca = `Zqx${Date.now() % 100000}`;
const password = process.env.E2E_PERSONAS_PASSWORD ?? "";
const PAQUETE_BASE = "Zqx501 Ciclo";

const PERSONAS = {
  tecnica: {
    nombre: "Zqx Técnica",
    email: "zqx-tecnica@example.com",
    permisos: ["Paquetes", "Armar paquetes", "Insumos", "Cargar insumos", "Servicios fijos"],
    pestanas: ["Paquetes", "Insumos", "Servicios fijos"],
  },
  administracion: {
    nombre: "Zqx Administración",
    email: "zqx-administracion@example.com",
    permisos: ["Insumos", "Costos", "Servicios fijos", "Editar servicios fijos", "Servicios en %", "Editar servicios en %"],
    pestanas: ["Insumos", "Servicios fijos", "Servicios en %"],
  },
  gerente: {
    nombre: "Zqx Gerente",
    email: "zqx-gerente@example.com",
    permisos: [
      "Paquetes",
      "Aprobar versiones",
      "Insumos",
      "Costos",
      "Servicios fijos",
      "Editar servicios fijos",
      "Servicios en %",
      "Editar servicios en %",
    ],
    pestanas: ["Paquetes", "Insumos", "Servicios fijos", "Servicios en %"],
  },
  revisor: {
    nombre: "Zqx Revisor de cortes",
    email: "zqx-revisor@example.com",
    permisos: ["Paquetes"],
    pestanas: ["Paquetes"],
  },
} as const;

type Persona = keyof typeof PERSONAS;
const TODAS = ["Paquetes", "Insumos", "Servicios fijos", "Servicios en %"];
const RUTA: Record<string, string> = {
  Paquetes: "/catalogo/paquetes",
  Insumos: "/catalogo/insumos",
  "Servicios fijos": "/catalogo/fijos",
  "Servicios en %": "/catalogo/porcentajes",
};

function escapar(texto: string) {
  return texto.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Un clic antes de que React tome la página no abre el menú: se reintenta hasta que abre.
async function elegirDelMenu(page: Page, menu: Locator, opcion: string) {
  const item = page.getByRole("button", { name: opcion });
  await expect(async () => {
    await menu.click();
    await expect(item).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
  await item.click();
}

async function asegurarPersona(admin: Page, p: (typeof PERSONAS)[Persona]) {
  await admin.goto("/usuarios");
  await expect(admin.getByRole("button", { name: "Nuevo usuario" })).toBeVisible();
  const fila = admin.locator("div.row").filter({ has: admin.getByText(p.nombre, { exact: true }) });
  if ((await fila.count()) === 0) {
    await admin.getByRole("button", { name: "Nuevo usuario" }).click();
    const alta = panel(admin);
    await alta.getByLabel("Nombre").fill(p.nombre);
    await alta.getByLabel("Email").fill(p.email);
    await alta.getByLabel("Contraseña").fill(password);
    await alta.getByRole("button", { name: "Crear usuario" }).click();
    await expect(alta).toBeHidden();
    await expect(fila).toBeVisible();
  }
  await elegirDelMenu(admin, fila.getByRole("button", { name: "Más acciones" }), "Permisos");
  const permisos = panel(admin);
  const bloque = permisos.locator("div.border-b").filter({ has: admin.getByText(/^Cat[aá]logo$/) });
  let cambio = false;
  for (const permiso of p.permisos) {
    const casilla = bloque.getByRole("checkbox", { name: new RegExp(`^${escapar(permiso)}`) });
    if (!(await casilla.isChecked())) {
      await casilla.check();
      cambio = true;
    }
  }
  await permisos.getByRole("button", { name: cambio ? "Guardar" : "Cancelar" }).click();
  await expect(permisos).toBeHidden();
}

async function entrar(browser: Browser, quien: Persona) {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  await page.goto("/login");
  await page.getByLabel("Email").fill(PERSONAS[quien].email);
  await page.getByLabel("Contraseña", { exact: true }).fill(password);
  await page.getByRole("button", { name: "Ingresar" }).click();
  await expect(page).not.toHaveURL(/\/login/, { timeout: 30_000 });
  return page;
}

// El cliente de la app, con la sesión de la persona: lo que un usuario puede pedirle a PostgREST sin pasar por las pantallas.
async function clienteDe(quien: Persona) {
  const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    auth: { persistSession: false },
  });
  const { error } = await supabase.auth.signInWithPassword({ email: PERSONAS[quien].email, password });
  expect(error).toBeNull();
  return supabase;
}

async function confirmar(page: Page, boton: string) {
  await page.getByRole("dialog").last().getByRole("button", { name: boton, exact: true }).click();
}

// El loading.tsx ya mandó el 200 cuando notFound() corre: el código HTTP no dice nada, lo dice la página.
async function sinAcceso(page: Page, ruta: string) {
  await page.goto(ruta);
  await expect(page.getByText("No encontramos esta página, o no tenés acceso."), ruta).toBeVisible();
}

// La campana de la página actual, recargada: los avisos se leen al abrir.
async function avisos(page: Page) {
  await page.reload();
  const bandeja = page.getByRole("dialog").last();
  await expect(async () => {
    await page.getByRole("button", { name: /^Notificaciones/ }).click();
    await expect(bandeja.getByText("Notificaciones").first()).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
  return bandeja;
}

const buscar = (page: Page, texto: string) => page.getByPlaceholder(/^Buscar/).fill(texto);

test.describe.serial("Catálogo, por persona", () => {
  const paginas = {} as Record<Persona, Page>;
  const insumo = `${marca} Perfil de prueba`;
  const fijo = `${marca} Flete`;
  const servicioPct = `${marca} Garantía`;
  const paquete = `${marca} Paquete`;
  let rutaVersion = "";

  test.beforeAll(async ({ browser }) => {
    test.setTimeout(180_000);
    expect(password, "Falta E2E_PERSONAS_PASSWORD en .env.test").not.toBe("");
    const { ctx, page } = await como(browser, "admin");
    for (const p of Object.values(PERSONAS)) await asegurarPersona(page, p);
    await ctx.close();
    for (const quien of Object.keys(PERSONAS) as Persona[]) paginas[quien] = await entrar(browser, quien);
  });

  test("cada persona ve sus pestañas y las demás rutas no existen", async () => {
    test.setTimeout(240_000);
    for (const quien of Object.keys(PERSONAS) as Persona[]) {
      const page = paginas[quien];
      const { pestanas } = PERSONAS[quien];
      await page.goto("/catalogo");
      await expect(page, quien).toHaveURL(new RegExp(RUTA[pestanas[0]]));
      // Sin esperar el contenido, "no está la pestaña" pasa con la página todavía cargando.
      await expect(page.getByPlaceholder(/^Buscar/), quien).toBeVisible();
      const ajenas = TODAS.filter((tab) => !(pestanas as readonly string[]).includes(tab));
      for (const tab of TODAS) {
        const enlace = page.getByRole("main").getByRole("link", { name: tab, exact: true });
        // Con una sola pestaña, la barra no se dibuja.
        await expect(enlace, `${quien} · ${tab}`).toHaveCount(!ajenas.includes(tab) && pestanas.length > 1 ? 1 : 0);
      }
      for (const tab of ajenas) await sinAcceso(page, RUTA[tab]);
    }
  });

  test("la base no le da a nadie lo que su pantalla le esconde", async () => {
    const tecnica = await clienteDe("tecnica");
    const revisor = await clienteDe("revisor");
    const administracion = await clienteDe("administracion");
    const gerente = await clienteDe("gerente");

    for (const [quien, c] of [["tecnica", tecnica], ["revisor", revisor]] as const) {
      const costos = await c.from("catalogo_costos").select("id").limit(1);
      expect(costos.data ?? [], `${quien} lee catalogo_costos`).toHaveLength(0);
      const vigentes = await c.rpc("catalogo_costos_vigentes");
      expect(Array.isArray(vigentes.data) ? vigentes.data : [], `${quien} pide costos vigentes`).toHaveLength(0);
      const pct = await c.from("catalogo_porcentajes").select("id").limit(1);
      expect(pct.data ?? [], `${quien} lee servicios en %`).toHaveLength(0);
      const insumos = await c.from("catalogo_insumos").select("id, nombre").limit(1);
      expect(insumos.data ?? [], `${quien} lee nombres de insumos`).toHaveLength(1);
    }

    const versiones = await administracion.from("catalogo_versiones").select("id").limit(1);
    expect(versiones.data ?? [], "administración lee versiones").toHaveLength(0);
    const piezas = await administracion.from("catalogo_piezas").select("id").limit(1);
    expect(piezas.data ?? [], "administración lee piezas").toHaveLength(0);
    const costosAdm = await administracion.from("catalogo_costos").select("id").limit(1);
    expect(costosAdm.data ?? [], "administración lee costos").toHaveLength(1);

    const costosGer = await gerente.from("catalogo_costos").select("id").limit(1);
    expect(costosGer.data ?? [], "gerente lee costos").toHaveLength(1);
  });

  test("Técnica carga un insumo y no ve costos", async () => {
    const page = paginas.tecnica;
    await page.goto("/catalogo/insumos");
    await expect(page.getByRole("button", { name: "Cargar costos" })).toHaveCount(0);
    await page.getByRole("button", { name: "Nuevo insumo" }).click();
    const alta = panel(page);
    await alta.getByLabel("Nombre").fill(insumo);
    await alta.getByLabel("Categoría").selectOption({ label: "Perfiles YL" });
    await alta.getByLabel("Unidad").selectOption({ index: 0 });
    await alta.getByRole("button", { name: "Guardar" }).click();
    await expect(alta).toBeHidden();

    await buscar(page, insumo);
    const fila = page.getByRole("button", { name: new RegExp(escapar(insumo)) });
    await expect(fila).toBeVisible();
    await expect(fila.getByText("Sin costo")).toHaveCount(0);
    await fila.click();
    const ficha = panel(page);
    await expect(ficha.getByRole("button", { name: "Editar" })).toBeVisible();
    await expect(ficha.getByRole("button", { name: "Cargar costo" })).toHaveCount(0);
    await expect((await avisos(page)).getByText(insumo)).toHaveCount(0);
  });

  test("Administración le carga el costo, sin poder editarlo, y el aviso desaparece", async () => {
    const page = paginas.administracion;
    await page.goto("/catalogo/insumos");
    await expect((await avisos(page)).getByText(insumo).first()).toBeVisible();
    await expect((await avisos(paginas.gerente)).getByText(insumo).first()).toBeVisible();
    await page.goto("/catalogo/insumos");
    await expect(page.getByRole("button", { name: "Nuevo insumo" })).toHaveCount(0);
    await buscar(page, insumo);
    const fila = page.getByRole("button", { name: new RegExp(escapar(insumo)) });
    await expect(fila.getByText("Sin costo")).toBeVisible();
    await fila.click();
    const ficha = panel(page);
    await expect(ficha.getByRole("button", { name: "Editar" })).toHaveCount(0);
    await ficha.getByRole("button", { name: "Cargar costo" }).click();
    const costos = panel(page);
    await costos.getByLabel(`Costo nuevo de ${insumo}`, { exact: false }).fill("1234");
    await costos.getByRole("button", { name: "Revisar" }).click();
    await expect(costos.getByText("Primer costo")).toBeVisible();
    await costos.getByRole("button", { name: "Guardar" }).click();
    await expect(costos.getByText("Primer costo")).toBeHidden();
    await expect(page.getByText("Sin costo")).toHaveCount(0);
    await expect((await avisos(page)).getByText(insumo)).toHaveCount(0);
    await expect((await avisos(paginas.gerente)).getByText(insumo)).toHaveCount(0);
  });

  test("Administración da de alta un servicio fijo y un servicio en %, y el gerente lo revierte", async () => {
    test.setTimeout(120_000);
    const adm = paginas.administracion;
    await adm.goto("/catalogo/fijos");
    await adm.getByRole("button", { name: "Nuevo servicio", exact: true }).click();
    const altaFijo = panel(adm);
    await altaFijo.getByLabel("Nombre").fill(fijo);
    await altaFijo.getByLabel("Categoría").selectOption({ label: "Zqx508 Servicios" });
    await altaFijo.getByLabel(/^Costo/).fill("500");
    await altaFijo.getByRole("button", { name: "Guardar" }).click();
    await expect(altaFijo).toBeHidden();
    await buscar(adm, fijo);
    await expect(adm.getByRole("button", { name: new RegExp(escapar(fijo)) })).toBeVisible();

    await adm.goto("/catalogo/porcentajes");
    await adm.getByRole("button", { name: /Nuevo servicio en %/ }).click();
    const altaPct = panel(adm);
    await altaPct.getByLabel("Nombre").fill(servicioPct);
    await altaPct.getByLabel("Porcentaje (%)").fill("1");
    await altaPct.getByLabel("Opcional").check();
    await altaPct.getByRole("button", { name: "Guardar" }).click();
    await expect(adm).toHaveURL(/\/catalogo\/porcentajes\/[0-9a-f-]{36}/);
    const rutaPct = new URL(adm.url()).pathname;

    const ger = paginas.gerente;
    await ger.goto(rutaPct);
    await ger.getByRole("button", { name: "Revertir" }).click();
    await confirmar(ger, "Revertir");
    await expect(ger.getByText("De baja", { exact: true }).first()).toBeVisible();
  });

  test("Técnica duplica, ve qué frena el envío y manda a revisión sin ver precios", async () => {
    test.setTimeout(120_000);
    const page = paginas.tecnica;
    await page.goto("/catalogo/paquetes");
    await buscar(page, PAQUETE_BASE);
    await page.getByRole("link", { name: new RegExp(PAQUETE_BASE) }).first().click();
    await page.getByRole("link", { name: /^v1 · / }).click();
    await expect(page.getByRole("heading", { name: `${PAQUETE_BASE} · v1` })).toBeVisible();

    await elegirDelMenu(page, page.getByRole("main").getByRole("button", { name: "Más acciones" }), "Duplicar paquete");
    const modal = page.getByRole("dialog").last();
    await modal.getByLabel("Nombre del paquete nuevo").fill(paquete);
    await modal.getByRole("button", { name: "Duplicar" }).click();
    await expect(page.getByRole("heading", { name: `${paquete} · v1` })).toBeVisible();
    rutaVersion = new URL(page.url()).pathname;

    await expect(page.getByRole("heading", { name: "Probar el despiece", exact: true })).toBeVisible();
    await expect(page.getByText("Moneda del precio")).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Aprobar" })).toHaveCount(0);

    // Una pieza sin materiales frena el envío; al sacarla, deja de frenarlo.
    await page.getByRole("link", { name: "Editar" }).click();
    await expect(page.getByRole("heading", { name: "Editar v1" })).toBeVisible();
    await page.getByRole("button", { name: /Sumar pieza/ }).click();
    const alta = panel(page);
    await alta.getByLabel("Nombre").fill(`${marca} Pieza`);
    await alta.getByRole("button", { name: "Guardar" }).click();
    await expect(alta).toBeHidden();
    await expect(page.getByText(/frena(n)? el envío/)).toBeVisible();
    const pieza = page.locator("div.card").filter({ hasText: `${marca} Pieza` });
    await elegirDelMenu(page, pieza.getByRole("button", { name: "Más acciones" }).first(), "Sacar");
    await confirmar(page, "Sacar");
    await expect(pieza).toHaveCount(0);

    await page.goto(rutaVersion);
    await page.getByRole("button", { name: "Enviar a revisión" }).click();
    await confirmar(page, "Enviar");
    await expect(page.getByRole("button", { name: "Retirar de revisión" })).toBeVisible();
  });

  test("la base frena lo que cada persona no puede hacer, aunque lo pida sin pasar por la pantalla", async () => {
    const version = rutaVersion.split("/").pop() ?? "";
    const tecnica = await clienteDe("tecnica");
    const revisor = await clienteDe("revisor");
    const administracion = await clienteDe("administracion");
    const gerente = await clienteDe("gerente");
    const sinPermiso = (quien: string, r: { error: { code?: string; message: string } | null }) =>
      expect(r.error?.code, `${quien}: ${JSON.stringify(r.error)}`).toBe("42501");

    for (const [quien, c] of [["tecnica", tecnica], ["revisor", revisor], ["administracion", administracion]] as const) {
      sinPermiso(`${quien} aprueba`, await c.rpc("catalogo_version_aprobar", { p_version: version }));
      sinPermiso(`${quien} devuelve`, await c.rpc("catalogo_version_devolver", { p_version: version, p_motivo: "Zqx" }));
    }
    for (const [quien, c] of [["gerente", gerente], ["revisor", revisor], ["administracion", administracion]] as const) {
      sinPermiso(`${quien} retira`, await c.rpc("catalogo_version_retirar", { p_version: version }));
    }

    const { data: variante } = await gerente.from("catalogo_variantes").select("id").eq("activo", true).limit(1).single();
    const filas = [{ variante_id: variante?.id, costo: 1, moneda: "USD_OFICIAL" }];
    for (const [quien, c] of [["tecnica", tecnica], ["revisor", revisor]] as const) {
      sinPermiso(`${quien} carga costos`, await c.rpc("catalogo_costos_cargar", { p_filas: filas, p_confirmar_rojo: true }));
    }

    const { data: unInsumo } = await gerente.from("catalogo_insumos").select("id").eq("nombre", insumo).single();
    for (const [quien, c] of [["gerente", gerente], ["administracion", administracion], ["revisor", revisor]] as const) {
      const r = await c.from("catalogo_insumos").update({ activo: false }).eq("id", unInsumo?.id).select("id");
      expect(r.data ?? [], `${quien} da de baja un insumo`).toHaveLength(0);
    }
    const renombrada = await revisor.from("catalogo_versiones").update({ nombre: "Zqx" }).eq("id", version).select("id");
    expect(renombrada.data ?? [], "revisor renombra una versión").toHaveLength(0);

    const { data: sigue } = await gerente.from("catalogo_versiones").select("estado, nombre").eq("id", version).single();
    expect(sigue).toEqual({ estado: "en_revision", nombre: paquete });
    const { data: activo } = await gerente.from("catalogo_insumos").select("activo").eq("id", unInsumo?.id).single();
    expect(activo?.activo).toBe(true);
  });

  test("quien revisa cortes ve el despiece, sin precio ni botones", async () => {
    const page = paginas.revisor;
    await page.goto("/catalogo/paquetes");
    await expect(page.getByRole("button", { name: "Nuevo paquete" })).toHaveCount(0);
    await expect(page.getByRole("link", { name: "Precios de referencia" })).toHaveCount(0);
    await expect(page.getByText(/^Por revisar/)).toHaveCount(0);

    await page.goto(rutaVersion);
    await expect(page.getByRole("heading", { name: `${paquete} · v1` })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Probar el despiece", exact: true })).toBeVisible();
    await expect(page.getByText("Moneda del precio")).toHaveCount(0);
    for (const boton of ["Aprobar", "Devolver", "Retirar de revisión", "Más acciones"]) {
      await expect(page.getByRole("main").getByRole("button", { name: boton }), boton).toHaveCount(0);
    }
    await page.getByRole("button", { name: "Calcular" }).click();
    await expect(page.getByText(/× /).first()).toBeVisible();
    await expect(page.getByText("Precio de venta")).toHaveCount(0);
    await expect(page.getByText("Costo del despiece")).toHaveCount(0);
    await expect(page.getByRole("main").getByText(/\$/)).toHaveCount(0);

    await sinAcceso(page, `${rutaVersion}/editar`);
    await sinAcceso(page, "/catalogo/paquetes/referencia");
  });

  test("el gerente devuelve con motivo, Técnica lo lee y reenvía, y el gerente publica", async () => {
    test.setTimeout(120_000);
    const motivo = `${marca} falta revisar la hoja`;
    const ger = paginas.gerente;
    await ger.goto("/catalogo/paquetes");
    await expect(ger.getByRole("button", { name: "Nuevo paquete" })).toHaveCount(0);
    await expect(ger.getByRole("link", { name: new RegExp(`${paquete} · v1`) })).toBeVisible();
    await (await avisos(ger)).getByText(`Espera revisión: ${paquete}`).click();
    await expect(ger).toHaveURL(new RegExp(`${rutaVersion}$`));
    await expect(ger.getByRole("heading", { name: "Probar el despiece y el precio" })).toBeVisible();
    await expect(ger.getByRole("link", { name: "Editar" })).toHaveCount(0);
    await ger.getByRole("button", { name: "Calcular" }).click();
    await expect(ger.getByText("Precio de venta")).toBeVisible();
    await expect(ger.getByText("Costo del despiece")).toBeVisible();
    await expect(ger.getByText("Sin precio", { exact: true })).toHaveCount(0);

    await ger.getByRole("button", { name: "Devolver" }).click();
    const devolver = ger.getByRole("dialog").last();
    await devolver.getByLabel("Motivo").fill(motivo);
    await devolver.getByRole("button", { name: "Devolver" }).click();
    await expect(devolver).toBeHidden();

    const tec = paginas.tecnica;
    await tec.goto(rutaVersion);
    await expect(tec.getByText(motivo).first()).toBeVisible();
    await tec.getByRole("button", { name: "Enviar a revisión" }).click();
    await confirmar(tec, "Enviar");
    await expect(tec.getByRole("button", { name: "Retirar de revisión" })).toBeVisible();

    await ger.goto(rutaVersion);
    await ger.getByRole("button", { name: "Aprobar" }).click();
    await confirmar(ger, "Aprobar");
    await expect(ger.getByRole("main").getByText("Publicad", { exact: false }).first()).toBeVisible();
    await expect(ger.getByRole("button", { name: "Aprobar" })).toHaveCount(0);

    await tec.goto(rutaVersion);
    await expect(tec.getByRole("button", { name: "Versión nueva desde v1" })).toBeVisible();
    const deTecnica = await avisos(tec);
    await expect(deTecnica.getByText(`Devolvieron ${paquete}`)).toBeVisible();
    await expect(deTecnica.getByText(motivo)).toBeVisible();
    await expect(deTecnica.getByText(`Aprobaron ${paquete}`)).toBeVisible();

    await ger.goto("/catalogo/paquetes/referencia");
    await expect(ger.getByRole("main").getByText(paquete).first()).toBeVisible();
    await expect((await avisos(ger)).getByText(`Espera revisión: ${paquete}`)).toHaveCount(0);

    await paginas.revisor.goto("/catalogo/paquetes");
    await expect((await avisos(paginas.revisor)).getByText(marca)).toHaveCount(0);
  });
});
