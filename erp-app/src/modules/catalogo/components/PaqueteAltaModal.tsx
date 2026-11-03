"use client";

import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import { crearPaquete } from "../actions";
import { paqueteAltaSchema, type Categoria, type PaqueteAltaForm } from "../types";

// El paquete nace con su v1 vacía, en borrador: se arma en el editor.
export function PaqueteAltaModal({ categorias, onClose }: { categorias: Categoria[]; onClose: () => void }) {
  const router = useRouter();
  const { register, handleSubmit, formState } = useForm<PaqueteAltaForm>({
    resolver: zodResolver(paqueteAltaSchema),
    defaultValues: { nombre: "", categoria_id: "" },
  });
  const { errors, isSubmitting } = formState;

  async function guardar(d: PaqueteAltaForm) {
    const r = await crearPaquete(d);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success(`Se creó ${d.nombre}: v1 en borrador`);
    router.push(`/catalogo/paquetes/versiones/${r.version_id}`);
  }

  return (
    <FormModal
      title="Nuevo paquete"
      confirmLabel="Crear"
      onClose={onClose}
      onSubmit={handleSubmit(guardar)}
      enviando={isSubmitting}
      hayCambios={formState.isDirty}
    >
      <Campo id="paquete-nombre" label="Nombre" requerido error={errors.nombre}>
        <input id="paquete-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
      </Campo>
      <Campo id="paquete-categoria" label="Categoría" requerido error={errors.categoria_id}>
        <select
          id="paquete-categoria"
          aria-required
          className={claseInput(errors.categoria_id)}
          {...register("categoria_id")}
        >
          <option value="">Elegí una</option>
          {categorias
            .filter((c) => c.activo)
            .map((c) => (
              <option key={c.id} value={c.id}>
                {c.nombre}
              </option>
            ))}
        </select>
      </Campo>
      <p className="t-caption">
        El nombre y la categoría son de la versión: cambiarlos después de publicada pide una versión nueva.
      </p>
    </FormModal>
  );
}
