function has_hx(el) {
    const attrs = el.attributes;
    return !!(attrs['hx-get'] || attrs['hx-get'] || attrs['hx-post'] || attrs['hx-put'] || attrs['hx-patch']);
}

function updateSlimSelectData(slimSelect, raw) {
    const data = Array.from(raw);
    const selected = slimSelect.getSelected()[0];

    for (let i = 0; i < data.length; ++i) {
        const value = data[i].value || data[i].text;
        if (value == selected) {
            data[i] = {
                value: data[i].value,
                text: data[i].text,
                selected: true,
            };
        }
    }

    slimSelect.setData(data);
}

function getSlimSelectRangeData(slimSelect, raw) {
    const result = raw.match(/^(\d+)-(\d+)(\?)?$/);
    if (result !== null) {
        const selected = slimSelect.getSelected()[0];
        const first = Number(result[1]);
        const last = Number(result[2]);
        const data = [];
        if (result[3] == '?') {
            if (!selected) {
                data.push({ text: '', selected: true });
            } else {
                data.push({ text: '' });
            }
        }
        const delta = first > last ? -1 : 1;
        for (let i = first; i != last; i += delta) {
            const value = '' + i;
            if (selected == value) {
                data.push({ text: value, selected: true });
            } else {
                data.push({ text: value });
            }
        }
        return data;
    }
    return undefined;
}

const select_options = {};

htmx.onLoad(content => {
    const selects = content.querySelectorAll(".slimselect");
    for (const select of selects) {
        //const hx = has_hx(select);

        const slimSelect = new SlimSelect({
            select: select,
            events: {
                afterChange: _ => select.dispatchEvent(new Event('ss:afterChange'))
            },
        });

        select.addEventListener('htmx:beforeSwap', _ => slimSelect.destroy());
        
        const options_url = select.dataset.options;
        if (options_url) {
            const rangeData = getSlimSelectRangeData(slimSelect, options_url);
            if (rangeData) {
                slimSelect.setData(rangeData);
            } else if (select_options[options_url] !== undefined) {
                select_options[options_url].then(data => updateSlimSelectData(slimSelect, data));
            } else {
                const promise = fetch(options_url, {
                    method: 'GET',
                    headers: { 'Accept': 'application/json' },
                }).then(response => response.json());
                select_options[options_url] = promise;
                promise.then(data => updateSlimSelectData(slimSelect, data));
            }
        }
    }

    const sortables = content.querySelectorAll(".sortable");
    for (const sortable of sortables) {
        const hx = has_hx(sortable);
        const sortableInstance = new Sortable(sortable, {
            animation: 150,
            ghostClass: '.sortable_ghost',
            dragClass: '.sortable_dragging',
            filter: '.unsortable, .htmx-indicator',
            handle: '.sort_handle',

            onMove: evt => {
                return !evt.related.classList.contains('htmx-indicator');
            },

            // Disable sorting on the `end` event
            onEnd: evt => {
                if (hx) {
                    sortableInstance.option("disabled", true);
                }
            }
        });

        if (hx) {
            sortable.addEventListener("htmx:afterSwap", () => {
                sortableInstance.option("disabled", false);
            });
        }
    }

});
