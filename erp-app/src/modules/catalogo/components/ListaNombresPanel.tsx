"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Archive, ArchiveRestore, Pencil } from "lucide-react";
import { toast } from "sonner";
import { claseInput } from "@/components/ui/Campo";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { RightPanel } from "@/components/ui/RightPanel";
import { nombreAltaSchema } from "../types";

type Item = { id: string; nombre: string; activo: boolean };
type Resultado = { success: true } | { success: false; error: string };

// Categorías (de los tres tipos) y colores siguen la misma regla: el nombre se edita hasta tener algo
// adentro y la baja pide que no haya nada activo. Lo frena la base (CA006, CA007): el panel solo llama.
export function ListaNombresPanel({
  titulo,
  regla,
  nueva,
  items,
  puedeEditar,
  onCrear,
  onRenombrar,
  onActivar,
  onClose,
}: {
  titulo: string;
  regla: string;
  // "Nueva categoría", "Nuevo color": el placeholder del alta.
  nueva: string;
  items: Item[];
  puedeEditar: boolean;
  onCrear: (nombre: string) => Promise<Resultado>;
  onRenombrar: (id: string, nombre: string) => Promise<Resultado>;
  onActivar: (id: string, activo: boolean) => Promise<Resultado>;
  onClose: () => void;
}) {
  const [renombrando, setRenombrando] = useState<string | null>(null);
  const ordenados = [...items.filter((i) => i.activo), ...items.filter((i) => !i.activo)];

  async function activar(item: Item) {
    const r = await onActivar(item.id, !item.activo);
    if (!r.success) toast.error(r.error);
    else toast.success(item.activo ? `Se dio de baja ${item.nombre}` : `Se reactivó ${item.nombre}`);
  }

  return (
    <RightPanel title={titulo} subtitle={regla} onClose={onClose}>
      <div className="flex flex-col gap-4 overflow-y-auto p-5">
        {puedeEditar && (
          <NombreForm
            label={nueva}
            boton="Sumar"
            onGuardar={async (nombre) => {
              const r = await onCrear(nombre);
              if (r.success) toast.success(`Se sumó ${nombre}`);
              return r;
            }}
          />
        )}
        {ordenados.length === 0 ? (
          <p className="t-body-m">Todavía no hay nada cargado.</p>
        ) : (
          <ul className="flex flex-col rounded-lg border border-border">
            {ordenados.map((item) => (
              <li key={item.id} className="row flex items-center gap-2 border-b border-border last:border-b-0">
                {renombrando === item.id ? (
                  <div className="flex-1">
                    <NombreForm
                      label={`Nombre de ${item.nombre}`}
                      boton="Guardar"
                      inicial={item.nombre}
                      onCancelar={() => setRenombrando(null)}
                      onGuardar={async (nombre) => {
                        const r = await onRenombrar(item.id, nombre);
                        if (r.success) {
                          toast.success("Nombre guardado");
                          setRenombrando(null);
                        }
                        return r;
                      }}
                    />
                  </div>
                ) : (
                  <>
                    <span className={`t-body-m min-w-0 flex-1 truncate ${item.activo ? "" : "text-text-tertiary"}`}>
                      {item.nombre}
                    </span>
                    {!item.activo && <span className="badge badge-neutral shrink-0">De baja</span>}
                    {puedeEditar && (
                      <OverflowMenu
                        items={[
                          ...(item.activo
                            ? [
                                {
                                  label: "Renombrar",
                                  icon: <Pencil size={14} strokeWidth={1.75} />,
                                  onClick: () => setRenombrando(item.id),
                                },
                              ]
                            : []),
                          {
                            label: item.activo ? "Dar de baja" : "Reactivar",
                            icon: item.activo ? (
                              <Archive size={14} strokeWidth={1.75} />
                            ) : (
                              <ArchiveRestore size={14} strokeWidth={1.75} />
                            ),
                            onClick: () => activar(item),
                            destructive: item.activo,
                          },
                        ]}
                      />
                    )}
                  </>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
    </RightPanel>
  );
}

function NombreForm({
  label,
  boton,
  inicial = "",
  onGuardar,
  onCancelar,
}: {
  label: string;
  boton: string;
  inicial?: string;
  onGuardar: (nombre: string) => Promise<Resultado>;
  onCancelar?: () => void;
}) {
  const { register, handleSubmit, reset, formState } = useForm<{ nombre: string }>({
    resolver: zodResolver(nombreAltaSchema),
    defaultValues: { nombre: inicial },
  });
  const { errors, isSubmitting } = formState;

  return (
    <form
      className="flex flex-col gap-1"
      onSubmit={handleSubmit(async ({ nombre }) => {
        const r = await onGuardar(nombre);
        if (!r.success) toast.error(r.error);
        else if (!onCancelar) reset({ nombre: "" });
      })}
    >
      <div className="flex gap-2">
        <input aria-label={label} placeholder={label} className={claseInput(errors.nombre)} {...register("nombre")} />
        <button type="submit" className="btn btn-primary shrink-0" disabled={isSubmitting}>
          {boton}
        </button>
        {onCancelar && (
          <button type="button" className="btn btn-secondary shrink-0" onClick={onCancelar}>
            Cancelar
          </button>
        )}
      </div>
      {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
    </form>
  );
}
