import { notFound } from "next/navigation";
import { getUsuarioActualId } from "@/lib/usuarios";
import { idSchema } from "@/lib/validacion";
import { puedeVerTodas } from "@/modules/obras/permissions";
import { getCandidatos, getNombres, getObras } from "@/modules/obras/queries";
import { ObrasView } from "@/modules/obras/components/ObrasView";
import { puedeVerPresupuestos } from "@/modules/presupuestos/permissions";
import { getEnCotizacionDeContratadas } from "@/modules/presupuestos/queries";

// Todas, también las desactivadas; sin alta, que una obra nueva es de quien la carga.
export default async function TodasPage(props: PageProps<"/obras/todas">) {
  const yo = await getUsuarioActualId();
  if (!yo || !(await puedeVerTodas())) notFound();
  const { responsable } = await props.searchParams;

  const [obras, nombres, candidatos, enCotizacion] = await Promise.all([
    getObras({ inactivas: true }),
    getNombres(),
    getCandidatos(),
    puedeVerPresupuestos().then((ve) => (ve ? getEnCotizacionDeContratadas() : undefined)),
  ]);

  return (
    <ObrasView
      obras={obras}
      yo={yo}
      nombres={nombres}
      enCotizacion={enCotizacion}
      todas={{
        recibibles: candidatos.map((c) => c.id),
        responsable: idSchema.safeParse(responsable).success ? (responsable as string) : null,
      }}
    />
  );
}
