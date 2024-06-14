function has_hx(el) {
    const attrs = el.attributes;
    return !!(attrs['hx-get'] || attrs['hx-get'] || attrs['hx-post'] || attrs['hx-put'] || attrs['hx-patch']);
}

function update_slim_select_data(slimSelect, raw) {
    const data = Array.from(raw);
    const selected = slimSelect.getSelected()[0];

    let placeholder_index = -1;
    let found_selected = false;
    for (let i = 0; i < data.length; ++i) {
        const value = data[i].value || data[i].text;
        if (data[i].placeholder) placeholder_index = i;
        if (value == selected) {
            data[i] = {
                value: data[i].value,
                text: data[i].text,
                selected: true,
            };
            found_selected = true;
        }
    }

    if (!found_selected) {
        const old_data = slimSelect.getData();
        for (let option of old_data) {
            if (option.value == selected) {
                option.selected = true;
                data.splice(placeholder_index + 1, 0, option);
                break;
            }
        }
    }

    slimSelect.setData(data);
}

function get_slim_select_range_data(slimSelect, raw) {
    const result = raw.match(/^(\d+)-(\d+)(\?)?$/);
    if (result !== null) {
        const selected = slimSelect.getSelected()[0];
        const first = Number(result[1]);
        const last = Number(result[2]);
        const data = [];
        let found_selected = false;
        const delta = first > last ? -1 : 1;
        for (let i = first; i != last; i += delta) {
            const value = '' + i;
            if (selected == value) {
                data.push({ text: value, selected: true });
                found_selected = true;
            } else {
                data.push({ text: value });
            }
        }

        if (!found_selected) {
            const old_data = slimSelect.getData();
            for (let option of old_data) {
                if (option.value == selected) {
                    option.selected = true;
                    data.unshift(option);
                    break;
                }
            }
        }

        const placeholder = { placeholder: true, text: 'Select...', value: '' };
        if (result[3] == '?') placeholder.text = ' ';
        if (!selected) placeholder.selected = true;
        data.unshift(placeholder);

        return data;
    }
    return undefined;
}

const select_options = {};

htmx.onLoad(content => {
    const selects = content.querySelectorAll("select.slimselect");
    for (const select of selects) {
        //const hx = has_hx(select);

        let search_handler = undefined;
        const search_url = select.dataset.searchUrl;
        if (search_url) {
            search_handler = async (search, currentData) => {
                const params = new URLSearchParams();
                params.set('name', search);
                const response = await fetch(search_url, {
                    method: 'POST',
                    headers: { 'Accept': 'application/json' },
                    body: params,
                });
                return await response.json();
            };
        }

        let changed = false;
        let open = false;

        const events = {
            beforeOpen: _ => open = true,
            afterClose: _ => {
                open = false;
                if (changed) {
                    select.dispatchEvent(new Event('ss:afterChange'));
                    changed = false;
                }
            },
            afterChange: _ => {
                if (open) {
                    slim_select.close();
                    changed = true;
                } else {
                    select.dispatchEvent(new Event('ss:afterChange'));
                }
            },
            search: search_handler,
        };

        if (select.dataset.addable !== undefined) {
            events.addable = value => value;
        }

        const slim_select = new SlimSelect({
            select: select,
            settings: {
                allowDeselect: select.dataset.deselectable !== undefined,
            },
            events
        });

        const options_url = select.dataset.options;
        if (options_url) {
            const range_data = get_slim_select_range_data(slim_select, options_url);
            if (range_data) {
                slim_select.setData(range_data);
            } else if (select_options[options_url] !== undefined) {
                select_options[options_url].then(data => update_slim_select_data(slim_select, data));
            } else {
                const promise = fetch(options_url, {
                    method: 'GET',
                    headers: { 'Accept': 'application/json' },
                }).then(response => response.json());
                select_options[options_url] = promise;
                promise.then(data => update_slim_select_data(slim_select, data));
            }
        }

    }

    const sortables = content.querySelectorAll(".sortable");
    for (const sortable of sortables) {
        const hx = has_hx(sortable);
        const sortable_instance = new Sortable(sortable, {
            animation: 150,
            ghostClass: '.sortable_ghost',
            dragClass: '.sortable_dragging',
            filter: '.unsortable, .htmx-indicator',
            handle: '.sort_handle',
            preventOnFilter: false,

            onMove: evt => {
                const classes = evt.related.classList;
                return !classes.contains('htmx-indicator') && !classes.contains('unsortable');
            },

            // Disable sorting on the `end` event
            onEnd: evt => {
                if (hx) {
                    sortable_instance.option("disabled", true);
                }
            }
        });

        if (hx) {
            sortable.addEventListener("htmx:afterSwap", () => {
                sortable_instance.option("disabled", false);
            });
        }
    }

});

document.addEventListener('htmx:beforeCleanupElement', evt => {
    const el = evt.detail.elt;
    if (el.tagName == 'SELECT' && el.classList.contains('slimselect') && el.slim) {
        el.slim.destroy();
        el.slim = undefined;
    }
});
