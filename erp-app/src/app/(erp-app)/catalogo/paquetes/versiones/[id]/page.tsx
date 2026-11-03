import { notFound } from "next/navigation";
import { idSchema } from "@/lib/validacion";
import { calcular } from "@/modules/catalogo/actions";
import { puedeAprobar, puedeArmar, puedeVerPaquetes } from "@/modules/catalogo/permissions";
import {
  getCasosCalculados,
  getCategorias,
  getContenido,
  getFrena,
  getInsumosBasicos,
  getMonedaPrincipal,
  getOferta,
  getVersion,
} from "@/modules/catalogo/queries";
import { VersionView } from "@/modules/catalogo/components/VersionView";

export default async function VersionPage(props: PageProps<"/catalogo/paquetes/versiones/[id]">) {
  const { id } = await props.params;
  if (!(await puedeVerPaquetes()) || !idSchema.safeParse(id).success) notFound();

  const version = await getVersion(id);
  if (!version) notFound();
  const abierta = version.estado === "borrador" || version.estado === "en_revision";

  const [contenido, categorias, insumos, oferta, casos, frena, armar, aprobar, monedaPrincipal] = await Promise.all([
    getContenido(id),
    getCategorias("paquete"),
    getInsumosBasicos(),
    getOferta(id),
    getCasosCalculados(id),
    abierta ? getFrena(id) : Promise.resolve(null),
    puedeArmar(),
    puedeAprobar(),
    getMonedaPrincipal(),
  ]);

  // Abre con el primer caso de prueba: son las medidas que eligió Técnica para revisarla.
  const caso = contenido.casos[0] ?? null;
  const publicada = version.paquete.versiones.find((v) => v.estado === "publicado");
  const r = await calcular({
    version_id: id,
    entrada: caso?.entrada ?? {},
    precio: aprobar
      ? {
          moneda: monedaPrincipal,
          opcionales: [],
          comparar_con: version.estado === "en_revision" && publicada ? publicada.id : null,
        }
      : null,
  });

  return (
    <VersionView
      version={version}
      contenido={contenido}
      categorias={categorias}
      insumos={insumos}
      frena={frena}
      oferta={oferta}
      casos={casos}
      inicial={{
        caso,
        resultado: r.success ? r.resultado : null,
        comparado: r.success ? r.comparado : null,
      }}
      puedeArmar={armar}
      puedeAprobar={aprobar}
      monedaPrincipal={monedaPrincipal}
    />
  );
}
