defmodule Flop.Phoenix.Table do
  @moduledoc false

  use Phoenix.Component

  alias Flop.Phoenix.Misc
  alias Phoenix.LiveView.JS

  require Logger

  @spec default_opts() :: [Flop.Phoenix.table_option()]
  def default_opts do
    [
      container: false,
      container_attrs: [class: "table-container"],
      no_results_content: Phoenix.HTML.raw("<p>No results.</p>"),
      symbol_asc: "▴",
      symbol_attrs: [class: "order-direction"],
      symbol_desc: "▾",
      symbol_unsorted: nil,
      table_attrs: [],
      tbody_attrs: [],
      tbody_td_attrs: [],
      tbody_tr_attrs: [],
      thead_attrs: [],
      th_wrapper_attrs: [],
      thead_th_attrs: [],
      thead_tr_attrs: []
    ]
  end

  def merge_opts(opts) do
    default_opts()
    |> Misc.deep_merge(Misc.get_global_opts(:table))
    |> Misc.deep_merge(opts)
  end

  attr(:id, :string, required: true)
  attr(:meta, Flop.Meta, required: true)
  attr(:path, :any, required: true)
  attr(:on_sort, JS)
  attr(:target, :string, required: true)
  attr(:caption, :string, required: true)
  attr(:opts, :any, required: true)
  attr(:col, :any)
  attr(:items, :list, required: true)
  attr(:foot, :any, required: true)
  attr(:row_id, :any, default: nil)
  attr(:row_click, JS, default: nil)
  attr(:row_item, :any, required: true)
  attr(:action, :any, required: true)

  def render(assigns) do
    assigns =
      with %{items: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table id={@id} {@opts[:table_attrs]}>
      <caption :if={@caption}>{@caption}</caption>
      <.maybe_colgroup col={@col ++ @action} />
      <thead {@opts[:thead_attrs]}>
        <tr {@opts[:thead_tr_attrs]}>
          <.header_column
            :for={col <- @col}
            on_sort={@on_sort}
            field={col[:field]}
            label={col[:label]}
            sortable={sortable?(col[:field], @meta.schema)}
            directions={col[:directions]}
            meta={@meta}
            thead_th_attrs={
              merge_attrs(@opts[:thead_th_attrs], col, :thead_th_attrs)
            }
            symbol_asc={@opts[:symbol_asc]}
            symbol_desc={@opts[:symbol_desc]}
            symbol_unsorted={@opts[:symbol_unsorted]}
            symbol_attrs={@opts[:symbol_attrs]}
            th_wrapper_attrs={
              merge_attrs(@opts[:th_wrapper_attrs], col, :th_wrapper_attrs)
            }
            path={@path}
            target={@target}
          />
          <.header_column
            :for={action <- @action}
            field={nil}
            label={action[:label]}
            sortable={false}
            meta={@meta}
            thead_th_attrs={
              merge_attrs(@opts[:thead_th_attrs], action, :thead_th_attrs)
            }
            path={nil}
            target={@target}
          />
        </tr>
      </thead>
      <tbody
        id={@id <> "-tbody"}
        phx-update={match?(%Phoenix.LiveView.LiveStream{}, @items) && "stream"}
        {@opts[:tbody_attrs]}
      >
        <tr
          :for={item <- @items}
          id={@row_id && @row_id.(item)}
          {maybe_invoke_options_callback(@opts[:tbody_tr_attrs], item)}
        >
          <td
            :for={col <- @col}
            {merge_td_attrs(@opts[:tbody_td_attrs], col, item)}
            phx-click={@row_click && @row_click.(item)}
          >
            {render_slot(col, @row_item.(item))}
          </td>
          <td
            :for={action <- @action}
            {merge_td_attrs(@opts[:tbody_td_attrs], action, item)}
          >
            {render_slot(action, @row_item.(item))}
          </td>
        </tr>
      </tbody>
      <tfoot :if={@foot != []}>{render_slot(@foot)}</tfoot>
    </table>
    """
  end

  defp merge_attrs(base_attrs, col, key) when is_atom(key) do
    attrs = Map.get(col, key, [])

    base_attrs
    |> Keyword.merge(attrs)
    |> add_combined_classes(col, key)
  end

  # Hilfsfunktion zum Hinzufügen der Klassen in der richtigen Reihenfolge
  defp add_combined_classes(attrs, col, :thead_th_attrs) do
    Keyword.update(attrs, :class, "", fn existing ->
      [existing, col[:td_th_class], col[:th_class]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
    end)
  end

  defp add_combined_classes(attrs, col, :tbody_td_attrs) do
    Keyword.update(attrs, :class, "", fn existing ->
      [existing, col[:td_th_class], col[:td_class]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
    end)
  end

  defp add_combined_classes(attrs, _col, _key), do: attrs

  defp merge_td_attrs(tbody_td_attrs, col, item) do
    attrs =
      col
      |> Map.get(:tbody_td_attrs, [])
      |> maybe_invoke_options_callback(item)

    merge_attrs(tbody_td_attrs, col, :tbody_td_attrs)
  end

  defp maybe_invoke_options_callback(option, item) when is_function(option) do
    option.(item)
  end

  defp maybe_invoke_options_callback(option, _item), do: option

  defp maybe_colgroup(assigns) do
    ~H"""
    <colgroup :if={Enum.any?(@col, &(&1[:col_style] || &1[:col_class]))}>
      <col
        :for={col <- @col}
        {reject_empty_values(style: col[:col_style], class: col[:col_class])}
      />
    </colgroup>
    """
  end

  defp reject_empty_values(attrs) do
    Enum.reject(attrs, fn {_, v} -> v in ["", nil] end)
  end

  attr(:meta, Flop.Meta, required: true)
  attr(:field, :atom, required: true)
  attr(:label, :any, required: true)
  attr(:path, :any, required: true)
  attr(:on_sort, JS)
  attr(:target, :string, required: true)
  attr(:sortable, :boolean, required: true)
  attr(:thead_th_attrs, :list, required: true)
  attr(:directions, :any)
  attr(:symbol_asc, :any)
  attr(:symbol_desc, :any)
  attr(:symbol_unsorted, :any)
  attr(:symbol_attrs, :list)
  attr(:th_wrapper_attrs, :list)
  attr(:td_th_class, :string)

  defp header_column(%{sortable: true} = assigns) do
    direction = order_direction(assigns.meta.flop, assigns.field)
    assigns = assign(assigns, :order_direction, direction)

    sort_path_options =
      if directions = assigns[:directions],
        do: [directions: directions],
        else: []

    sort_path =
      build_path(
        assigns[:path],
        assigns[:meta],
        assigns[:field],
        sort_path_options
      )

    assigns = assign(assigns, :sort_path, sort_path)

    # Verwende td_th_class direkt aus den assigns
    th_attrs =
      assigns.thead_th_attrs
      |> Keyword.update(:class, assigns[:td_th_class], fn existing ->
        [existing, assigns[:td_th_class]]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
      end)

    assigns = assign(assigns, :thead_th_attrs, th_attrs)

    ~H"""
    <th {@thead_th_attrs} aria-sort={aria_sort(@order_direction)}>
      <span {@th_wrapper_attrs}>
        <.sort_link
          path={@sort_path}
          on_sort={@on_sort}
          field={@field}
          label={@label}
          target={@target}
        />
        <.arrow
          direction={@order_direction}
          symbol_asc={@symbol_asc}
          symbol_desc={@symbol_desc}
          symbol_unsorted={@symbol_unsorted}
          {@symbol_attrs}
        />
      </span>
    </th>
    """
  end

  defp header_column(%{sortable: false} = assigns) do
    # Verwende td_th_class direkt aus den assigns
    th_attrs =
      assigns.thead_th_attrs
      |> Keyword.update(:class, assigns[:td_th_class], fn existing ->
        [existing, assigns[:td_th_class]]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
      end)

    assigns = assign(assigns, :thead_th_attrs, th_attrs)

    ~H"""
    <th {@thead_th_attrs}>{@label}</th>
    """
  end

  defp aria_sort(:desc), do: "descending"
  defp aria_sort(:desc_nulls_last), do: "descending"
  defp aria_sort(:desc_nulls_first), do: "descending"
  defp aria_sort(:asc), do: "ascending"
  defp aria_sort(:asc_nulls_last), do: "ascending"
  defp aria_sort(:asc_nulls_first), do: "ascending"
  defp aria_sort(_), do: nil

  attr(:direction, :atom, required: true)
  attr(:symbol_asc, :any, required: true)
  attr(:symbol_desc, :any, required: true)
  attr(:symbol_unsorted, :any, required: true)
  attr(:rest, :global)

  defp arrow(%{direction: direction} = assigns)
       when direction in [:asc, :asc_nulls_first, :asc_nulls_last] do
    ~H"<span {@rest}>{@symbol_asc}</span>"
  end

  defp arrow(%{direction: direction} = assigns)
       when direction in [:desc, :desc_nulls_first, :desc_nulls_last] do
    ~H"<span {@rest}>{@symbol_desc}</span>"
  end

  defp arrow(%{direction: nil, symbol_unsorted: nil} = assigns) do
    ~H""
  end

  defp arrow(%{direction: nil} = assigns) do
    ~H"<span {@rest}>{@symbol_unsorted}</span>"
  end

  attr(:field, :atom, required: true)
  attr(:label, :string, required: true)
  attr(:path, :string)
  attr(:on_sort, JS)
  attr(:target, :string)

  defp sort_link(%{on_sort: nil, path: path} = assigns)
       when is_binary(path) do
    ~H"""
    <.link patch={@path}>{@label}</.link>
    """
  end

  defp sort_link(%{} = assigns) do
    ~H"""
    <.link
      patch={@path}
      phx-click={@on_sort}
      phx-target={@target}
      phx-value-order={@field}
    >
      {@label}
    </.link>
    """
  end

  defp order_direction(
         %Flop{order_by: [field | _], order_directions: [direction | _]},
         field
       ) do
    direction
  end

  defp order_direction(%Flop{}, _), do: nil

  defp sortable?(nil, _), do: false
  defp sortable?(_, nil), do: true

  defp sortable?(field, module) do
    field in (module |> struct() |> Flop.Schema.sortable())
  end

  defp build_path(nil, _, _, _), do: nil

  defp build_path(
         path,
         meta,
         field,
         opts
       ) do
    Flop.Phoenix.build_path(
      path,
      Flop.push_order(meta.flop, field, opts),
      backend: meta.backend,
      for: meta.schema
    )
  end
end
