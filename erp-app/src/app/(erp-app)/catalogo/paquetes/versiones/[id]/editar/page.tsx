import { notFound, redirect } from "next/navigation";
import { idSchema } from "@/lib/validacion";
import { puedeArmar, puedeVerPaquetes } from "@/modules/catalogo/permissions";
import {
  getCategorias,
  getColores,
  getContenido,
  getFrena,
  getInsumosBasicos,
  getVersion,
} from "@/modules/catalogo/queries";
import { EditorView } from "@/modules/catalogo/components/editor/EditorView";

// Solo un borrador se edita (CA012): cualquier otra vuelve a la ficha de la versión.
export default async function EditarVersionPage(props: PageProps<"/catalogo/paquetes/versiones/[id]/editar">) {
  const { id } = await props.params;
  if (!(await puedeVerPaquetes()) || !(await puedeArmar()) || !idSchema.safeParse(id).success) notFound();

  const version = await getVersion(id);
  if (!version) notFound();
  if (version.estado !== "borrador") redirect(`/catalogo/paquetes/versiones/${id}`);

  const [contenido, categorias, colores, insumos, frena] = await Promise.all([
    getContenido(id),
    getCategorias("paquete"),
    getColores(),
    getInsumosBasicos(),
    getFrena(id),
  ]);

  return (
    <EditorView
      version={version}
      contenido={contenido}
      categorias={categorias}
      colores={colores}
      insumos={insumos}
      frena={frena}
    />
  );
}
