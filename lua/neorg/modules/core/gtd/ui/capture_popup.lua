--[[
    Submodule responsible for creating API for capture popup
--]]

local module = neorg.modules.extend("core.gtd.ui.capture_popup", "core.gtd.ui")

---@class core.gtd.ui
module.public = {
    --- Creates the selection popup for capturing a task
    show_capture_popup = function()
        -- Generate views selection popup
        local buffer = module.required["core.ui"].create_split("Quick Actions")

        if not buffer then
            return
        end

        local selection = module.required["core.ui"].begin_selection(buffer):listener(
            "destroy",
            { "<Esc>" },
            function(self)
                self:destroy()
            end
        )

        -- Reset state of previous fetches
        module.required["core.queries.native"].delete_content()

        selection:title("Capture"):blank():concat(module.private.capture_task)
        module.public.display_messages()
    end,
}

--- @class private_core.gtd.ui
module.private = {

    --- Content of the capture popup
    ---@param selection core.ui.selection
    ---@return core.ui.selection
    capture_task = function(selection)
        return selection:title("Add a task"):blank():prompt("Task", {
            callback = function(text)
                ---@type core.gtd.queries.task
                local task = {}
                task.content = text

                selection:push_page()

                selection
                    :title("Add informations")
                    :blank()
                    :text("Task: " .. task.content)
                    :blank()
                    :text("General informations")
                    :concat(function()
                        return module.private.generate_default_flags(selection, task, "contexts", "c")
                    end)
                    :concat(function()
                        return module.private.generate_default_flags(selection, task, "waiting.for", "w")
                    end)
                    :blank()
                    :text("Dates")
                    :concat(function()
                        return module.private.generate_date_flags(selection, task, "time.due", "d")
                    end)
                    :concat(function()
                        return module.private.generate_date_flags(selection, task, "time.start", "s")
                    end)
                    :blank()
                    :text("Insert")
                    :concat(function()
                        return module.private.generate_project_flags(selection, task, "p")
                    end)
                    :flag("x", "Add to cursor position", function()
                        local cursor = vim.api.nvim_win_get_cursor(0)
                        local location = { cursor[1] - 1, 0 }
                        module.required["core.gtd.queries"].create(
                            "task",
                            task,
                            0,
                            location,
                            false,
                            { newline = false }
                        )
                    end)
                    :flag("<CR>", "Add to inbox", function()
                        local workspace = neorg.modules.get_module_config("core.gtd.base").workspace
                        local workspace_path = module.required["core.norg.dirman"].get_workspace(workspace)

                        local files = module.required["core.norg.dirman"].get_norg_files(workspace)
                        local inbox = neorg.modules.get_module_config("core.gtd.base").default_lists.inbox
                        if not vim.tbl_contains(files, inbox) then
                            log.error([[ Inbox file is not from gtd workspace.
                            Please verify if the file exists in your gtd workspace.
                            Type :messages to show the full error report
                            ]])
                            return
                        end

                        local uri = vim.uri_from_fname(workspace_path .. "/" .. inbox)
                        local buf = vim.uri_to_bufnr(uri)
                        local end_row, projectAtEnd = module.required["core.gtd.queries"].get_end_document_content(buf)

                        module.required["core.gtd.queries"].create("task", task, buf, { end_row, 0 }, projectAtEnd)
                    end)

                return selection
            end,

            -- Do not pop or destroy the prompt when confirmed
            pop = false,
            destroy = false,
        })
    end,

    --- Generate flags for specific mode
    ---@param selection core.ui.selection
    ---@param task core.gtd.queries.task
    ---@param mode string #Date mode to use: waiting_for|contexts
    ---@param flag string #The flag to use
    ---@return core.ui.selection
    generate_default_flags = function(selection, task, mode, flag)
        if not vim.tbl_contains({ "contexts", "waiting.for" }, mode) then
            log.error("Invalid mode")
            return
        end

        local title = (function()
            if mode == "contexts" then
                return "Add Contexts"
            elseif mode == "waiting.for" then
                return "Add Waiting Fors"
            end
        end)()

        return selection:rflag(flag, title, {
            destroy = false,
            callback = function()
                selection
                    :listener("go-back", { "<BS>" }, function(self)
                        self:pop_page()
                    end)
                    :title(title)
                    :text("Separate multiple values with space")
                    :blank()
                    :prompt(title, {
                        callback = function(text)
                            if #text > 0 then
                                task[mode] = vim.split(text, " ", false)
                            end
                        end,
                        pop = true,
                        prompt_text = task[mode] and table.concat(task[mode], " ") or "",
                    })
            end,
        })
    end,

    --- Generate flags for specific mode (date related)
    ---@param selection table
    ---@param task core.gtd.queries.task
    ---@param mode string #Date mode to use: start|due
    ---@param flag string #The flag to use
    ---@return table #`selection`
    generate_date_flags = function(selection, task, mode, flag)
        local title = "Add a " .. mode .. " date"
        return selection:rflag(flag, title, function()
            selection
                :listener("go-back", { "<BS>" }, function(self)
                    self:pop_page()
                end)
                :title(title)
                :blank()
                :text("Static Times:")
                :flag("d", "Today", {
                    destroy = false,
                    callback = function()
                        task[mode] = module.required["core.gtd.queries"].date_converter("today")
                        selection:pop_page()
                    end,
                })
                :flag("t", "Tomorrow", {
                    destroy = false,
                    callback = function()
                        task[mode] = module.required["core.gtd.queries"].date_converter("tomorrow")
                        selection:pop_page()
                    end,
                })
                :flag("w", "Next week", {
                    destroy = false,
                    callback = function()
                        task[mode] = module.required["core.gtd.queries"].date_converter("1w")
                        selection:pop_page()
                    end,
                })
                :flag("m", "Next month", {
                    destroy = false,
                    callback = function()
                        task[mode] = module.required["core.gtd.queries"].date_converter("1m")
                        selection:pop_page()
                    end,
                })
                :flag("y", "Next year", {
                    destroy = false,
                    callback = function()
                        task[mode] = module.required["core.gtd.queries"].date_converter("1y")
                        selection:pop_page()
                    end,
                })
                :blank()
                :rflag("c", "Custom", {
                    destroy = false,
                    callback = function()
                        selection
                            :title("Custom Date")
                            :text("Allowed date: today, tomorrow, Xw, Xd, Xm, Xy (where X is a number)")
                            :text("You can even use 'mon', 'tue', 'wed' ... for the next weekday date")
                            :text("You can also use '2mon' for the 2nd monday that will come")
                            :blank()
                            :prompt("Due", {
                                callback = function(text)
                                    if #text > 0 then
                                        task[mode] = module.required["core.gtd.queries"].date_converter(text)

                                        if not task[mode] then
                                            log.error("Date format not recognized, please try again...")
                                        else
                                            selection:pop_page()
                                        end
                                    end
                                end,
                                pop = true,
                            })
                    end,
                })
        end)
    end,

    --- Generates projects flags when capturing a task to a project
    ---@param selection core.ui.selection
    ---@param task core.gtd.queries.task
    ---@param flag string
    ---@return core.ui.selection
    generate_project_flags = function(selection, task, flag)
        return selection:flag(flag, "Add to project", {
            callback = function()
                selection:push_page()

                selection:title("Add to project"):blank():text("Append task to existing project")

                -- Get all projects
                local projects = module.required["core.gtd.queries"].get("projects")
                --- @type core.gtd.queries.project
                projects = module.required["core.gtd.queries"].add_metadata(projects, "project")

                for i, project in pairs(projects) do
                    local f = module.private.create_flag(i)
                    -- NOTE: If there is more than 26 projects, will stop there
                    if not f then
                        selection:text("Too much projects to display...")
                        break
                    end

                    selection:flag(f, project.content, {
                        callback = function()
                            selection:push_page()

                            module.private.create_recursive_project_placement(
                                selection,
                                project.internal.node,
                                project.internal.bufnr,
                                project.content,
                                task,
                                true
                            )
                        end,
                        destroy = false,
                    })
                end

                selection:blank():text("Create new project"):flag("x", "Create new project", {
                    callback = function()
                        selection:push_page()
                        selection:title("Create a new project"):blank():prompt("Project name", {
                            callback = function(text)
                                --- @type core.gtd.queries.project
                                local project = {}
                                project.content = text

                                selection:push_page()
                                selection
                                    :title("Create a new project")
                                    :blank()
                                    :text("Project name: " .. project.content)
                                    :blank()

                                local files = module.required["core.gtd.helpers"].get_gtd_files()

                                if vim.tbl_isempty(files) then
                                    selection:text("No files found...")
                                    return
                                end

                                selection:text("Select project location")
                                for i, file in pairs(files) do
                                    local f = module.private.create_flag(i)
                                    if not f then
                                        selection:title("Too much content...")
                                        break
                                    end
                                    selection:flag(f, file, {
                                        callback = function()
                                            module.private.create_project(selection, file, task, project)
                                        end,
                                        destroy = false,
                                    })
                                end
                            end,
                            pop = false,
                            destroy = false,
                        })
                    end,
                    destroy = false,
                })
            end,
            destroy = false,
        })
    end,

    --- Generates flags to create a project
    ---@param selection core.ui.selection
    ---@param file string
    ---@param task core.gtd.queries.task
    ---@param project core.gtd.queries.project
    create_project = function(selection, file, task, project)
        local tree = {
            {
                query = { "all", "marker" },
                recursive = true,
            },
        }

        local workspace = neorg.modules.get_module_config("core.gtd.base").workspace
        local path = module.required["core.norg.dirman"].get_workspace(workspace)
        local bufnr = module.required["core.norg.dirman"].get_file_bufnr(path .. "/" .. file)
        local nodes = module.required["core.queries.native"].query_nodes_from_buf(tree, bufnr)
        local extracted_nodes = module.required["core.queries.native"].extract_nodes(nodes)

        local location
        if vim.tbl_isempty(nodes) then
            location = module.required["core.gtd.queries"].get_end_document_content(bufnr)
            if not location then
                log.error("Something is wrong in the " .. file .. " file")
                return
            end
            selection:destroy()
            module.required["core.gtd.queries"].create(
                "project",
                project,
                bufnr,
                { location, 0 },
                false,
                { newline = false }
            )
            module.required["core.gtd.queries"].create("task", task, bufnr, { location + 1, 2 }, false, {
                newline = false,
            })
        else
            selection:push_page()
            selection:title("Create a new project"):blank():text("Project name: " .. project.content):blank()
            selection:text("Select in which area of focus add this project")

            for i, marker_node in pairs(nodes) do
                local f = module.private.create_flag(i)
                if not f then
                    selection:title("Too much content...")
                    break
                end
                selection:flag(f, extracted_nodes[i]:sub(3), function()
                    local ts_utils = module.required["core.integrations.treesitter"].get_ts_utils()
                    local _, _, er, _ = ts_utils.get_node_range(marker_node[1])
                    module.required["core.gtd.queries"].create(
                        "project",
                        project,
                        bufnr,
                        { er, 0 },
                        false,
                        { newline = false }
                    )
                    module.required["core.gtd.queries"].create("task", task, bufnr, { er + 1, 2 }, false, {
                        newline = false,
                    })
                end)
            end

            selection:flag("<CR>", "None", function()
                location = module.required["core.gtd.queries"].get_end_document_content(bufnr)
                if not location then
                    log.error("Something is wrong in the " .. file .. " file")
                    return
                end
                selection:destroy()

                module.required["core.gtd.queries"].create(
                    "project",
                    project,
                    bufnr,
                    { location, 0 },
                    true,
                    { newline = false }
                )
                module.required["core.gtd.queries"].create("task", task, bufnr, { location + 2, 2 }, false, {
                    newline = false,
                })
            end)
        end
    end,

    --- Will try to descend the project and ask the user in which subheading append the task
    ---@param selection core.ui.selection
    ---@param node userdata
    ---@param bufnr number
    ---@param project_title string
    ---@param task core.gtd.queries.task
    ---@param is_project_root boolean
    create_recursive_project_placement = function(selection, node, bufnr, project_title, task, is_project_root)
        ---- Creates flags for generic lists from current node
        ---@param _node core.gtd.queries.project
        local function get_generic_lists(_node, _bufnr)
            local tree = {
                { query = { "all", "generic_list" } },
                { query = { "all", "carryover_tag_set" } },
            }
            local nodes = module.required["core.queries.native"].query_from_tree(_node, tree, _bufnr)

            if nodes and not vim.tbl_isempty(nodes) then
                return nodes
            end
        end

        --- Recursively creates subheadings flags
        ---@param _node userdata
        local function create_subheadings(_selection, _node, _bufnr)
            local node_type = _node:type()
            -- Get subheading level
            local heading_level = string.sub(node_type, -1)
            heading_level = tonumber(heading_level) + 1

            -- Get all direct subheadings
            local tree = {
                {
                    query = { "all", "heading" .. heading_level },
                },
            }

            local nodes = module.required["core.queries.native"].query_from_tree(_node, tree, _bufnr)
            local extracted_nodes = module.required["core.queries.native"].extract_nodes(nodes)

            for i, n in pairs(extracted_nodes) do
                local f = module.private.create_flag(i)
                if not f then
                    _selection:title("Too much subheadings...")
                    break
                end
                n = string.sub(n, heading_level + 2)
                _selection:flag(f, "Append to " .. n .. " (subheading)", {
                    callback = function()
                        _selection:push_page()
                        module.private.create_recursive_project_placement(
                            _selection,
                            nodes[i][1],
                            nodes[i][2],
                            project_title,
                            task,
                            false
                        )
                    end,
                    destroy = false,
                })
            end
        end

        selection:title(project_title):blank()

        local description = is_project_root and "Project root" or "Root of current subheading"
        local location

        selection:text("Where do you want to add the task ?")
        create_subheadings(selection, node, bufnr)
        selection:flag("<CR>", description, {
            callback = function()
                local generic_lists = get_generic_lists(node, bufnr)
                if generic_lists then
                    local ts_utils = module.required["core.integrations.treesitter"].get_ts_utils()

                    local last_list = generic_lists[#generic_lists]

                    local _, sc, er, _ = ts_utils.get_node_range(last_list[1])
                    if last_list[1]:type() == "carryover_tag_set" then
                        location = { er + 2, sc }
                    else
                        location = { er + 1, sc }
                    end
                else
                    location = module.required["core.gtd.queries"].get_end_project(node, bufnr)
                end

                module.required["core.gtd.queries"].create("task", task, bufnr, location, false, { newline = false })
                vim.cmd(string.format([[echom '%s']], 'Task added to "' .. project_title .. '".'))
            end,
            destroy = true,
        })
    end,

    --- Generates a flag from the alphabet.
    --- e.g If index == 2, flag generated will be `b`
    ---@param index number
    ---@return string
    create_flag = function(index)
        local alphabet = "abcdefghijklmnopqrstuvwxyz"
        index = (index % #alphabet)
        if index == 0 then
            return
        end

        return alphabet:sub(index, index)
    end,
}

return module
