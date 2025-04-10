#!/bin/sh

# push to origin target_sync_branch
push_new_commits() {
    write_out -1 'Pushing synced data to target branch.'

    # TODO: figure out how this would work in local mode...
    # update remote url with token since it is not persisted during checkout step when syncing from a private repo
    if [ -n "${INPUT_TARGET_REPO_TOKEN}" ]; then
        git remote set-url origin "https://${GITHUB_ACTOR}:${INPUT_TARGET_REPO_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
    fi

    # Create a new branch for changes
    BRANCH_NAME="sync-update-$(date +%Y%m%d%H%M%S)"
    git checkout -b "${BRANCH_NAME}"
    
    # Push to the new branch instead of directly to target branch
    # shellcheck disable=SC2086
    git push origin "${BRANCH_NAME}"
    PUSH_STATUS=$?
    
    if [ "${PUSH_STATUS}" != 0 ]; then
        # exit on push to new branch fail
        write_out "${PUSH_STATUS}" "Could not push changes to new branch."
        return
    fi
    
    # Create PR if GitHub token is available
    if [ -n "${INPUT_TARGET_REPO_TOKEN}" ]; then
        PR_TITLE="Sync updates from source repository"
        PR_BODY="This PR contains synchronized updates from the source repository."
        
        # Create PR using GitHub API
        PR_RESPONSE=$(curl -s -X POST \
            -H "Authorization: token ${INPUT_TARGET_REPO_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls" \
            -d "{\"title\":\"${PR_TITLE}\",\"body\":\"${PR_BODY}\",\"head\":\"${BRANCH_NAME}\",\"base\":\"${INPUT_TARGET_SYNC_BRANCH}\"}")
        
        # Check if PR was created successfully
        if echo "${PR_RESPONSE}" | grep -q "\"number\""; then
            PR_NUMBER=$(echo "${PR_RESPONSE}" | grep -o '\"number\":[^,]*' | cut -d ':' -f 2)
            write_out "0" "Successfully created PR #${PR_NUMBER} for changes."
            write_out "g" 'SUCCESS\n'
        else
            write_out "1" "Failed to create PR. API response: ${PR_RESPONSE}"
        fi
    else
        write_out "0" "Changes pushed to branch ${BRANCH_NAME}. Please create a PR manually."
        write_out "g" 'SUCCESS\n'
    fi
}
