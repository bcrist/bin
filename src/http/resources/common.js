htmx.onLoad(function (content) {
    const sortables = content.querySelectorAll(".sortable");
    for (const sortable of sortables) {
        const has_hx = !!(sortable.attributes['hx-get'] || sortable.attributes['hx-get'] || sortable.attributes['hx-post'] || sortable.attributes['hx-put'] || sortable.attributes['hx-patch']);
        const sortableInstance = new Sortable(sortable, {
            animation: 150,
            ghostClass: '.sortable-ghost',
            dragClass: '.sortable-dragging',
            filter: '.unsortable, .htmx-indicator',
            handle: '.sort-handle',

            onMove: evt => {
                return !evt.related.classList.contains('htmx-indicator');
            },

            // Disable sorting on the `end` event
            onEnd: evt => {
                if (has_hx) {
                    sortableInstance.option("disabled", true);
                }
            }
        });

        if (has_hx) {
            sortable.addEventListener("htmx:afterSwap", () => {
                sortableInstance.option("disabled", false);
            });
        }
    }
});
