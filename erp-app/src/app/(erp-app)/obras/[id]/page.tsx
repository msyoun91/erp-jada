import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { idSchema } from "@/lib/validacion";
import { getVinculosDe } from "@/modules/contactos/queries";
import { VinculosSeccion } from "@/modules/contactos/components/VinculosSeccion";
import { puedeAdministrar, puedeVerObras } from "@/modules/obras/permissions";
import { getCandidatos, getNombres, getObra } from "@/modules/obras/queries";
import { ObraView } from "@/modules/obras/components/ObraView";
import { LABEL_ESTADO, type EstadoObra } from "@/modules/obras/types";

// `?vincular={rol}` y `?estado={estado}`: los links de acción de Tareas abren
// la ficha con el panel o el cambio de estado a mano.
export default async function ObraPage(props: PageProps<"/obras/[id]">) {
  const { id } = await props.params;
  const { vincular, estado } = await props.searchParams;
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerObras()) || !idSchema.safeParse(id).success) notFound();

  const [datos, vinculos, nombres, candidatos, admin] = await Promise.all([
    getObra(id),
    getVinculosDe("obra", id),
    getNombres(),
    getCandidatos(),
    puedeAdministrar(),
  ]);
  if (!datos) notFound();

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
        />
      }
    />
  );
}
