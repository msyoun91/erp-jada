import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { idSchema } from "@/lib/validacion";
import { puedeAdministrar } from "@/modules/contactos/permissions";
import { getLadoFusion, getNombres } from "@/modules/contactos/queries";
import { FusionarView } from "@/modules/contactos/components/FusionarView";
import { getComisiones } from "@/modules/obras/queries";
import { textoComision } from "@/modules/obras/etiquetas";

// La función "fusionar" (`contactos_administrar`), dentro de la vista
// Contactos. `?tipo=persona|empresa&a={id}&b={id}`: se llega desde la ficha.
export default async function FusionarPage(props: PageProps<"/contactos/fusionar">) {
  const { tipo, a, b } = await props.searchParams;
  const yo = await getUsuarioActualId();
  if (
    !yo ||
    !(await puedeAdministrar()) ||
    (tipo !== "persona" && tipo !== "empresa") ||
    !idSchema.safeParse(a).success ||
    !idSchema.safeParse(b).success ||
    a === b
  )
    notFound();

  const [ladoA, ladoB, nombres] = await Promise.all([
    getLadoFusion(tipo, a as string),
    getLadoFusion(tipo, b as string),
    getNombres(),
  ]);
  if (!ladoA || !ladoB) notFound();

  // Con dos comisiones en la misma obra, el admin elige; solo las ve con la
  // obra a cargo (sin eso, queda la del vínculo por defecto).
  const comisiones = await getComisiones(
    [...ladoA.vinculos, ...ladoB.vinculos].filter((v) => v.ente === "obra").map((v) => v.id)
  );
  const activas = Object.fromEntries(comisiones.filter((c) => c.activo).map((c) => [c.vinculo_id, textoComision(c)]));

  return <FusionarView tipo={tipo} lados={[ladoA, ladoB]} comisiones={activas} nombres={nombres} yo={yo} />;
}
