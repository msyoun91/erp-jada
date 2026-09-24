export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      entes: {
        Row: {
          activo: boolean
          codigo: string
          created_at: string
          datos: string[]
          disparos: Database["public"]["Enums"]["tipo_evento"][]
          estados: unknown
          id: string
          modulo: string
          ruta: string
          submodulo: string
          tabla: unknown
          updated_at: string
        }
        Insert: {
          activo?: boolean
          codigo: string
          created_at?: string
          datos?: string[]
          disparos?: Database["public"]["Enums"]["tipo_evento"][]
          estados?: unknown
          id?: string
          modulo: string
          ruta: string
          submodulo: string
          tabla: unknown
          updated_at?: string
        }
        Update: {
          activo?: boolean
          codigo?: string
          created_at?: string
          datos?: string[]
          disparos?: Database["public"]["Enums"]["tipo_evento"][]
          estados?: unknown
          id?: string
          modulo?: string
          ruta?: string
          submodulo?: string
          tabla?: unknown
          updated_at?: string
        }
        Relationships: []
      }
      equipos: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          nombre: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          nombre: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          nombre?: string
          updated_at?: string
        }
        Relationships: []
      }
      equipos_miembros: {
        Row: {
          activo: boolean
          created_at: string
          equipo_id: string
          id: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          equipo_id: string
          id?: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          equipo_id?: string
          id?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "equipos_miembros_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "equipos_miembros_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      eventos: {
        Row: {
          actor_id: string | null
          created_at: string
          detalle: Json
          ente: string
          evento: Database["public"]["Enums"]["tipo_evento"]
          id: string
          registro_id: string
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          detalle?: Json
          ente: string
          evento: Database["public"]["Enums"]["tipo_evento"]
          id?: string
          registro_id: string
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          detalle?: Json
          ente?: string
          evento?: Database["public"]["Enums"]["tipo_evento"]
          id?: string
          registro_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "eventos_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "eventos_ente_fkey"
            columns: ["ente"]
            isOneToOne: false
            referencedRelation: "entes"
            referencedColumns: ["codigo"]
          },
        ]
      }
      submodulo_reglas: {
        Row: {
          activo: boolean
          id: string
          otro_id: string
          submodulo_id: string
          tipo: Database["public"]["Enums"]["tipo_regla_submodulo"]
        }
        Insert: {
          activo?: boolean
          id?: string
          otro_id: string
          submodulo_id: string
          tipo: Database["public"]["Enums"]["tipo_regla_submodulo"]
        }
        Update: {
          activo?: boolean
          id?: string
          otro_id?: string
          submodulo_id?: string
          tipo?: Database["public"]["Enums"]["tipo_regla_submodulo"]
        }
        Relationships: [
          {
            foreignKeyName: "submodulo_reglas_otro_id_fkey"
            columns: ["otro_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "submodulo_reglas_submodulo_id_fkey"
            columns: ["submodulo_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
        ]
      }
      submodulos: {
        Row: {
          activo: boolean
          codigo: string
          created_at: string
          delegable: boolean
          id: string
          modulo: string
          nombre: string
          orden: number
          tipo: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at: string
          vista_id: string | null
        }
        Insert: {
          activo?: boolean
          codigo: string
          created_at?: string
          delegable?: boolean
          id?: string
          modulo: string
          nombre: string
          orden?: number
          tipo: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at?: string
          vista_id?: string | null
        }
        Update: {
          activo?: boolean
          codigo?: string
          created_at?: string
          delegable?: boolean
          id?: string
          modulo?: string
          nombre?: string
          orden?: number
          tipo?: Database["public"]["Enums"]["tipo_submodulo"]
          updated_at?: string
          vista_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "submodulos_vista_id_fkey"
            columns: ["vista_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas: {
        Row: {
          activo: boolean
          asignado_equipo_id: string | null
          asignado_id: string | null
          created_at: string
          descripcion: string | null
          equipo_id: string | null
          espera_hasta: string | null
          espera_motivo: string | null
          estado: Database["public"]["Enums"]["estado_tarea"]
          hilo_id: string
          id: string
          motivo_rechazo: string | null
          paso_anterior_id: string | null
          prioridad: Database["public"]["Enums"]["prioridad_tarea"]
          resultado: string | null
          titulo: string
          updated_at: string
          vence: string | null
          vence_dias: number | null
        }
        Insert: {
          activo?: boolean
          asignado_equipo_id?: string | null
          asignado_id?: string | null
          created_at?: string
          descripcion?: string | null
          equipo_id?: string | null
          espera_hasta?: string | null
          espera_motivo?: string | null
          estado?: Database["public"]["Enums"]["estado_tarea"]
          hilo_id: string
          id?: string
          motivo_rechazo?: string | null
          paso_anterior_id?: string | null
          prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          resultado?: string | null
          titulo: string
          updated_at?: string
          vence?: string | null
          vence_dias?: number | null
        }
        Update: {
          activo?: boolean
          asignado_equipo_id?: string | null
          asignado_id?: string | null
          created_at?: string
          descripcion?: string | null
          equipo_id?: string | null
          espera_hasta?: string | null
          espera_motivo?: string | null
          estado?: Database["public"]["Enums"]["estado_tarea"]
          hilo_id?: string
          id?: string
          motivo_rechazo?: string | null
          paso_anterior_id?: string | null
          prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          resultado?: string | null
          titulo?: string
          updated_at?: string
          vence?: string | null
          vence_dias?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "tareas_asignado_equipo_id_fkey"
            columns: ["asignado_equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_asignado_id_fkey"
            columns: ["asignado_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilo_id_fkey"
            columns: ["hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_paso_anterior_fk"
            columns: ["paso_anterior_id", "hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id", "hilo_id"]
          },
        ]
      }
      tareas_ediciones: {
        Row: {
          activo: boolean
          actor_id: string | null
          anterior: string | null
          campo: string
          created_at: string
          hilo_id: string
          id: string
          nuevo: string | null
          ocultada_at: string | null
          ocultada_por: string | null
          tarea_id: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          actor_id?: string | null
          anterior?: string | null
          campo: string
          created_at?: string
          hilo_id: string
          id?: string
          nuevo?: string | null
          ocultada_at?: string | null
          ocultada_por?: string | null
          tarea_id?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          actor_id?: string | null
          anterior?: string | null
          campo?: string
          created_at?: string
          hilo_id?: string
          id?: string
          nuevo?: string | null
          ocultada_at?: string | null
          ocultada_por?: string | null
          tarea_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_ediciones_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_ediciones_hilo_id_fkey"
            columns: ["hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_ediciones_ocultada_por_fkey"
            columns: ["ocultada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_ediciones_tarea_fk"
            columns: ["tarea_id", "hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id", "hilo_id"]
          },
        ]
      }
      tareas_hilos: {
        Row: {
          activo: boolean
          created_at: string
          equipo_id: string | null
          estado: Database["public"]["Enums"]["estado_hilo"]
          id: string
          recurrencia_cantidad: number | null
          recurrencia_de: string | null
          recurrencia_unidad:
            | Database["public"]["Enums"]["recurrencia_unidad"]
            | null
          responsable_id: string
          resultado: string | null
          titulo: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          equipo_id?: string | null
          estado?: Database["public"]["Enums"]["estado_hilo"]
          id?: string
          recurrencia_cantidad?: number | null
          recurrencia_de?: string | null
          recurrencia_unidad?:
            | Database["public"]["Enums"]["recurrencia_unidad"]
            | null
          responsable_id?: string
          resultado?: string | null
          titulo: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          equipo_id?: string | null
          estado?: Database["public"]["Enums"]["estado_hilo"]
          id?: string
          recurrencia_cantidad?: number | null
          recurrencia_de?: string | null
          recurrencia_unidad?:
            | Database["public"]["Enums"]["recurrencia_unidad"]
            | null
          responsable_id?: string
          resultado?: string | null
          titulo?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_hilos_equipo_id_fkey"
            columns: ["equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilos_recurrencia_de_fkey"
            columns: ["recurrencia_de"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_hilos_responsable_id_fkey"
            columns: ["responsable_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_notas: {
        Row: {
          activo: boolean
          autor_id: string
          created_at: string
          hilo_id: string
          id: string
          ocultada_at: string | null
          ocultada_por: string | null
          tarea_id: string | null
          texto: string
          updated_at: string
        }
        Insert: {
          activo?: boolean
          autor_id?: string
          created_at?: string
          hilo_id: string
          id?: string
          ocultada_at?: string | null
          ocultada_por?: string | null
          tarea_id?: string | null
          texto: string
          updated_at?: string
        }
        Update: {
          activo?: boolean
          autor_id?: string
          created_at?: string
          hilo_id?: string
          id?: string
          ocultada_at?: string | null
          ocultada_por?: string | null
          tarea_id?: string | null
          texto?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_notas_autor_id_fkey"
            columns: ["autor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_notas_hilo_id_fkey"
            columns: ["hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas_hilos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_notas_ocultada_por_fkey"
            columns: ["ocultada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_notas_tarea_fk"
            columns: ["tarea_id", "hilo_id"]
            isOneToOne: false
            referencedRelation: "tareas"
            referencedColumns: ["id", "hilo_id"]
          },
        ]
      }
      tareas_plantillas: {
        Row: {
          activo: boolean
          copiada_de: string | null
          created_at: string
          descripcion: string | null
          dueno_id: string
          id: string
          nombre: string
          publicada: boolean
          updated_at: string
        }
        Insert: {
          activo?: boolean
          copiada_de?: string | null
          created_at?: string
          descripcion?: string | null
          dueno_id?: string
          id?: string
          nombre: string
          publicada?: boolean
          updated_at?: string
        }
        Update: {
          activo?: boolean
          copiada_de?: string | null
          created_at?: string
          descripcion?: string | null
          dueno_id?: string
          id?: string
          nombre?: string
          publicada?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tareas_plantillas_copiada_de_fkey"
            columns: ["copiada_de"]
            isOneToOne: false
            referencedRelation: "tareas_plantillas"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_plantillas_dueno_id_fkey"
            columns: ["dueno_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      tareas_plantillas_pasos: {
        Row: {
          activo: boolean
          asignado_equipo_id: string | null
          asignado_id: string | null
          created_at: string
          descripcion: string | null
          espera_anterior: boolean
          id: string
          orden: number
          plantilla_id: string
          prioridad: Database["public"]["Enums"]["prioridad_tarea"]
          titulo: string
          updated_at: string
          vence_dias: number | null
        }
        Insert: {
          activo?: boolean
          asignado_equipo_id?: string | null
          asignado_id?: string | null
          created_at?: string
          descripcion?: string | null
          espera_anterior?: boolean
          id?: string
          orden: number
          plantilla_id: string
          prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          titulo: string
          updated_at?: string
          vence_dias?: number | null
        }
        Update: {
          activo?: boolean
          asignado_equipo_id?: string | null
          asignado_id?: string | null
          created_at?: string
          descripcion?: string | null
          espera_anterior?: boolean
          id?: string
          orden?: number
          plantilla_id?: string
          prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          titulo?: string
          updated_at?: string
          vence_dias?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "tareas_plantillas_pasos_asignado_equipo_id_fkey"
            columns: ["asignado_equipo_id"]
            isOneToOne: false
            referencedRelation: "equipos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_plantillas_pasos_asignado_id_fkey"
            columns: ["asignado_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tareas_plantillas_pasos_plantilla_id_fkey"
            columns: ["plantilla_id"]
            isOneToOne: false
            referencedRelation: "tareas_plantillas"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_notificaciones: {
        Row: {
          activo: boolean
          actor_id: string | null
          created_at: string
          entidad: string
          entidad_id: string
          id: string
          leida_at: string | null
          tipo: Database["public"]["Enums"]["tipo_notificacion"]
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          actor_id?: string | null
          created_at?: string
          entidad: string
          entidad_id: string
          id?: string
          leida_at?: string | null
          tipo: Database["public"]["Enums"]["tipo_notificacion"]
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          actor_id?: string | null
          created_at?: string
          entidad?: string
          entidad_id?: string
          id?: string
          leida_at?: string | null
          tipo?: Database["public"]["Enums"]["tipo_notificacion"]
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_notificaciones_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_notificaciones_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_submodulos: {
        Row: {
          activo: boolean
          created_at: string
          id: string
          otorgada_por: string | null
          submodulo_id: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          id?: string
          otorgada_por?: string | null
          submodulo_id: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          id?: string
          otorgada_por?: string | null
          submodulo_id?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_submodulos_otorgada_por_fkey"
            columns: ["otorgada_por"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_submodulos_submodulo_id_fkey"
            columns: ["submodulo_id"]
            isOneToOne: false
            referencedRelation: "submodulos"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "usuario_submodulos_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_tutorial: {
        Row: {
          created_at: string
          id: string
          paso: string
          updated_at: string
          usuario_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          paso: string
          updated_at?: string
          usuario_id: string
        }
        Update: {
          created_at?: string
          id?: string
          paso?: string
          updated_at?: string
          usuario_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_tutorial_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuario_widgets: {
        Row: {
          created_at: string
          id: string
          updated_at: string
          usuario_id: string
          visible: boolean
          widget_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          updated_at?: string
          usuario_id: string
          visible?: boolean
          widget_id: string
        }
        Update: {
          created_at?: string
          id?: string
          updated_at?: string
          usuario_id?: string
          visible?: boolean
          widget_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "usuario_widgets_usuario_id_fkey"
            columns: ["usuario_id"]
            isOneToOne: false
            referencedRelation: "usuarios"
            referencedColumns: ["id"]
          },
        ]
      }
      usuarios: {
        Row: {
          activo: boolean
          created_at: string
          email: string
          id: string
          nombre: string
          telefono: string | null
          updated_at: string
        }
        Insert: {
          activo?: boolean
          created_at?: string
          email: string
          id: string
          nombre: string
          telefono?: string | null
          updated_at?: string
        }
        Update: {
          activo?: boolean
          created_at?: string
          email?: string
          id?: string
          nombre?: string
          telefono?: string | null
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      asignar_equipo: {
        Args: { p_admin: string; p_equipo: string | null; p_usuario: string }
        Returns: undefined
      }
      asignar_submodulos: {
        Args: { p_admin: string; p_submodulos: string[]; p_usuario: string }
        Returns: undefined
      }
      copiar_plantilla: { Args: { p_plantilla: string }; Returns: string }
      delegar_submodulos: {
        Args: { p_submodulos: string[]; p_usuario: string }
        Returns: undefined
      }
      designar_delegador: {
        Args: { p_admin: string; p_usuario: string }
        Returns: undefined
      }
      emitir_evento: {
        Args: {
          p_detalle?: Json
          p_ente: string
          p_evento: Database["public"]["Enums"]["tipo_evento"]
          p_registro_id: string
        }
        Returns: undefined
      }
      equipo_de: { Args: { p_usuario: string }; Returns: string }
      etiqueta_registro: {
        Args: { p_ente: string; p_id: string }
        Returns: string
      }
      fijar_delegables: {
        Args: { p_admin: string; p_submodulos: string[] }
        Returns: undefined
      }
      guardar_plantilla: {
        Args: {
          p_descripcion: string
          p_id: string
          p_nombre: string
          p_pasos: Json
        }
        Returns: string
      }
      mi_equipo: { Args: never; Returns: string }
      normalizar_telefono: { Args: { t: string }; Returns: string }
      notificaciones_actores: {
        Args: never
        Returns: {
          id: string
          nombre: string
        }[]
      }
      notificaciones_listar: {
        Args: { p_limite?: number }
        Returns: {
          actor: string
          created_at: string
          destino: string
          destino_id: string
          etiqueta: string
          id: string
          leida: boolean
          motivo: string
          tipo: Database["public"]["Enums"]["tipo_notificacion"]
        }[]
      }
      notificar: {
        Args: {
          p_actor_id: string
          p_entidad: string
          p_entidad_id: string
          p_tipo: Database["public"]["Enums"]["tipo_notificacion"]
          p_usuario_id: string
        }
        Returns: undefined
      }
      puede_ver_relacion: {
        Args: {
          p_ente: string
          p_ente_rel: string
          p_id: string
          p_id_rel: string
        }
        Returns: boolean
      }
      quitar_delegador: {
        Args: {
          p_admin: string
          p_heredero: string | null
          p_no_copiar?: string[]
          p_saliente: string
        }
        Returns: undefined
      }
      tareas_actua_como_asignado: {
        Args: { p_actor: string; p_equipo: string; p_usuario: string }
        Returns: boolean
      }
      tareas_asignables: {
        Args: never
        Returns: {
          equipo_id: string
          nombre: string
          pedido: boolean
          puede_recibir: boolean
          usuario_id: string
        }[]
      }
      tareas_bloquea: { Args: { p_paso: string }; Returns: boolean }
      tareas_cancelar_y_cerrar: {
        Args: { p_generar?: boolean; p_hilo: string; p_resultado?: string }
        Returns: undefined
      }
      tareas_completar_con_nota: {
        Args: { p_nota: string; p_resultado?: string; p_tarea: string }
        Returns: undefined
      }
      tareas_delegador_de: { Args: { p_equipo: string }; Returns: string }
      tareas_desactivar_hilo: { Args: { p_hilo: string }; Returns: undefined }
      tareas_desactivar_paso: { Args: { p_paso: string }; Returns: undefined }
      tareas_entregar: { Args: { p_usuario: string }; Returns: undefined }
      tareas_equipo_de_asignado: {
        Args: { p_equipo: string; p_usuario: string }
        Returns: string
      }
      tareas_es_pedido: {
        Args: { p_equipo: string; p_responsable: string; p_usuario: string }
        Returns: boolean
      }
      tareas_estado_al_abrir: {
        Args: {
          p_directo: boolean
          p_equipo: string
          p_responsable: string
          p_usuario: string
        }
        Returns: Database["public"]["Enums"]["estado_tarea"]
      }
      tareas_etiqueta: {
        Args: { p_id: string; p_tipo: string }
        Returns: string
      }
      tareas_hoy: { Args: never; Returns: string }
      tareas_insertar_antes: {
        Args: {
          p_asignado_equipo_id: string
          p_asignado_id: string
          p_descripcion: string
          p_prioridad?: Database["public"]["Enums"]["prioridad_tarea"]
          p_siguiente: string
          p_titulo: string
          p_vence?: string
          p_vence_dias?: number
        }
        Returns: string
      }
      tareas_puede_recibir: {
        Args: { p_equipo: string; p_usuario: string }
        Returns: boolean
      }
      tareas_puede_ver_hilo: {
        Args: {
          p_activo: boolean
          p_equipo: string
          p_hilo: string
          p_responsable: string
        }
        Returns: boolean
      }
      tareas_puede_ver_hilo_de: {
        Args: {
          p_activo: boolean
          p_equipo: string
          p_hilo: string
          p_responsable: string
          p_usuario: string
        }
        Returns: boolean
      }
      tareas_puede_ver_tarea: {
        Args: { p_activo: boolean; p_hilo: string }
        Returns: boolean
      }
      tareas_puede_ver_tarea_de: {
        Args: { p_activo: boolean; p_hilo: string; p_usuario: string }
        Returns: boolean
      }
      tareas_siguiente_efectivo: { Args: { p_paso: string }; Returns: string }
      tareas_transferir_hilo: {
        Args: { p_hilo: string; p_responsable: string }
        Returns: undefined
      }
      tiene_permiso: { Args: { p_codigo: string }; Returns: boolean }
      usar_plantilla: {
        Args: {
          p_asignados?: Json
          p_hilo?: string
          p_plantilla: string
          p_titulo?: string
        }
        Returns: string
      }
      usuario_tiene_permiso: {
        Args: { p_codigo: string; p_usuario: string }
        Returns: boolean
      }
    }
    Enums: {
      estado_hilo: "abierto" | "cerrado"
      estado_tarea:
        | "solicitada"
        | "pendiente"
        | "rechazada"
        | "completada"
        | "cancelada"
      prioridad_tarea: "baja" | "media" | "alta"
      recurrencia_unidad: "dia" | "mes"
      tipo_evento:
        | "alta"
        | "baja"
        | "reactivacion"
        | "estado"
        | "relacion_alta"
        | "relacion_baja"
        | "transferencia"
      tipo_notificacion:
        | "miembro_nuevo"
        | "permiso_otorgado"
        | "delegador_designado"
        | "tarea_asignada"
        | "pedido_recibido"
        | "paso_editado"
        | "pedido_aceptado"
        | "pedido_rechazado"
        | "paso_reabierto"
        | "hilo_transferido"
        | "paso_habilitado"
        | "paso_bloqueado"
        | "paso_reasignado"
        | "paso_quitado"
        | "paso_a_reasignar"
        | "paso_sumado"
        | "paso_huerfano"
        | "hilos_huerfanos"
        | "hilo_dado_de_baja"
        | "paso_dado_de_baja"
        | "paso_completado"
        | "paso_cancelado"
      tipo_regla_submodulo: "requiere" | "excluye"
      tipo_submodulo: "vista" | "funcion"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      estado_hilo: ["abierto", "cerrado"],
      estado_tarea: [
        "solicitada",
        "pendiente",
        "rechazada",
        "completada",
        "cancelada",
      ],
      prioridad_tarea: ["baja", "media", "alta"],
      recurrencia_unidad: ["dia", "mes"],
      tipo_evento: [
        "alta",
        "baja",
        "reactivacion",
        "estado",
        "relacion_alta",
        "relacion_baja",
        "transferencia",
      ],
      tipo_notificacion: [
        "miembro_nuevo",
        "permiso_otorgado",
        "delegador_designado",
        "tarea_asignada",
        "pedido_recibido",
        "paso_editado",
        "pedido_aceptado",
        "pedido_rechazado",
        "paso_reabierto",
        "hilo_transferido",
        "paso_habilitado",
        "paso_bloqueado",
        "paso_reasignado",
        "paso_quitado",
        "paso_a_reasignar",
        "paso_sumado",
        "paso_huerfano",
        "hilos_huerfanos",
        "hilo_dado_de_baja",
        "paso_dado_de_baja",
        "paso_completado",
        "paso_cancelado",
      ],
      tipo_regla_submodulo: ["requiere", "excluye"],
      tipo_submodulo: ["vista", "funcion"],
    },
  },
} as const
