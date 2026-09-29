import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { idSchema } from "@/lib/validacion";
import { getVinculosDe } from "@/modules/contactos/queries";
import { VinculosSeccion, type ExtraVinculo } from "@/modules/contactos/components/VinculosSeccion";
import { getHilosDeRegistro } from "@/modules/tareas/queries";
import { HilosDeRegistro } from "@/modules/tareas/components/HilosDeRegistro";
import { puedeAdministrar, puedeVerObras } from "@/modules/obras/permissions";
import { getCandidatos, getComisiones, getNombres, getObra } from "@/modules/obras/queries";
import { ComisionReferente } from "@/modules/obras/components/ComisionReferente";
import { textoComision } from "@/modules/obras/etiquetas";
import { ObraView } from "@/modules/obras/components/ObraView";
import { LABEL_ESTADO, type EstadoObra } from "@/modules/obras/types";

// `?vincular={rol}` y `?estado={estado}`: los links de acción de Tareas abren
// la ficha con el panel o el cambio de estado a mano.
export default async function ObraPage(props: PageProps<"/obras/[id]">) {
  const { id } = await props.params;
  const { vincular, estado } = await props.searchParams;
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerObras()) || !idSchema.safeParse(id).success) notFound();

  const [datos, vinculos, nombres, candidatos, admin, hilos] = await Promise.all([
    getObra(id),
    getVinculosDe("obra", id),
    getNombres(),
    getCandidatos(),
    puedeAdministrar(),
    getHilosDeRegistro("obra", id),
  ]);
  if (!datos) notFound();

  // La comisión va en la fila de cada referente; solo con la obra a cargo.
  const referentes = datos.aCargo ? vinculos.filter((v) => v.roles.includes("referente")) : [];
  const comisiones = await getComisiones(referentes.map((v) => v.id));
  const extras: Record<string, ExtraVinculo> = {};
  for (const v of referentes) {
    const suyas = comisiones.filter((c) => c.vinculo_id === v.id);
    const abierto = v.hasta === null;
    if (!abierto && suyas.length === 0) continue;
    const vigente = suyas.find((c) => c.activo);
    extras[v.id] = {
      detalle: <ComisionReferente vinculoId={v.id} comisiones={suyas} abierto={abierto} yo={yo} nombres={nombres} />,
      aviso: vigente
        ? `Tiene una comisión de ${textoComision(vigente)}: si se cierra, se saca o deja de ser referente, se da de baja.`
        : undefined,
    };
  }

  const estadoInicial = typeof estado === "string" && estado in LABEL_ESTADO ? (estado as EstadoObra) : null;

  return (
    <ObraView
      {...datos}
      yo={yo}
      admin={admin}
      nombres={nombres}
      candidatos={candidatos}
      estadoInicial={estadoInicial}
      contactos={
        <VinculosSeccion
          ente="obra"
          registroId={id}
          vinculos={vinculos}
          trabaja={datos.trabaja}
          vincular={typeof vincular === "string" ? vincular : null}
          extras={extras}
        />
      }
      hilos={<HilosDeRegistro {...hilos} yo={yo} />}
    />
  );
}
